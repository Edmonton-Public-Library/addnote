#!/s/sirsi/Unicorn/Bin/perl -w
####################################################
#
# Perl source file for project addnote 
# Purpose:
# Method:
#
# Takes barcodes on STDIN and adds a note to the associated account.
#    Copyright (C) 2014  Andrew Nisbet
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA 02110-1301, USA.
#
# This script was developed to cope with reciprocal borrowers. We have thousands, and we 
# want to add a note on all of their accounts to ask staff to change their accounts to 
# EPL-METRO. What ever your requirement, if you need to put a note on a lot of accounts
# this is the script for you. 
#
# It does not remove notes, merely adds a new one.
#
# Author:  Andrew Nisbet, Edmonton Public Library
# Created: Mon Nov 17 14:54:31 MST 2014
# Rev: 
#          0.4 - Add -q for quick note additions. 
#          0.3 - Remove duplicate definition of variable. 
#          0.2 - Make more efficient and better log output. 
#          0.1 - Dev. 
#
####################################################

use strict;
use warnings;
use vars qw/ %opt /;
use Getopt::Std;

# Environment setup required by cron to run script because its daemon runs
# without assuming any environment settings and we need to use sirsi's.
###############################################
# *** Edit these to suit your environment *** #
$ENV{'PATH'}  = qq{:/s/sirsi/Unicorn/Bincustom:/s/sirsi/Unicorn/Bin:/usr/bin:/usr/sbin};
$ENV{'UPATH'} = qq{/s/sirsi/Unicorn/Config/upath};
###############################################
my $VERSION   = qq{0.4};
my $TEMP_DIR           = `getpathname tmp`;
chomp $TEMP_DIR;
my $TIME               = `date +%H%M%S`;
chomp $TIME;
my $USER_ID   = "ADMIN";
my $STATION   = "PCGUI-DISP";
my @CLEAN_UP_FILE_LIST = (); # List of file names that will be deleted at the end of the script if ! '-t'.

#
# Message about this program and how to use it.
#
sub usage()
{
    print STDERR << "EOF";

	usage: $0 [-xU] [-m"Message string"] [-w work/dir]
addnote.pl reads customer account barcodes on STDIN and adds 
a message to the note field of each account if it exists. The 
slast activity of the user's account is not modified by adding a note
via this method.

 -m<message>: REQUIRED. Message for the note field. The message will be tested to 
              ensure it is not empty. Do not use '!' or other special characters in message.
 -q         : Quick add note, doesn't require -U. 
 -t         : Test mode. Doesn't remove any temporary files so you can debug stages of selection. 
 -U         : Actually do the updates to the account, otherwise
              just creates the flat user overlay file.
 -w<work/dir>: DEPRECATED The working directory '/tmp' by default.
 -x         : This (help) message.

example: $0 -x
 echo 21221012345678 | $0 -m"Note added." -U 
 cat user_barcodes.lst | $0 -m"Note added." -q
Version: $VERSION
EOF
    exit;
}

# Removes all the temp files created during running of the script.
# param:  List of all the file names to clean up.
# return: <none>
sub clean_up
{
	foreach my $file ( @CLEAN_UP_FILE_LIST )
	{
		if ( $opt{'t'} )
		{
			printf STDERR "preserving file '%s' for review.\n", $file;
		}
		else
		{
			if ( -e $file )
			{
				unlink $file;
			}
			else
			{
				printf STDERR "** Warning: file '%s' not found.\n", $file;
			}
		}
	}
}

# Writes data to a temp file and returns the name of the file with path.
# param:  unique name of temp file, like master_list, or 'hold_keys'.
# param:  data to write to file.
# return: name of the file that contains the list.
sub create_tmp_file( $$ )
{
	my $name    = shift;
	my $results = shift;
	my $master_file = "$TEMP_DIR/$name.$TIME";
	# Return just the file name if there are no results to report.
	return $master_file if ( ! $results );
	open FH, ">$master_file" or die "*** error opening '$master_file', $!\n";
	my @list = split '\n', $results;
	foreach my $line ( @list )
	{
		print FH "$line\n";
	}
	close FH;
	# Add it to the list of files to clean if required at the end.
	push @CLEAN_UP_FILE_LIST, $master_file;
	return $master_file;
}

# Adds a note using API server. Preserves last activity.
# param:  Input file name, barcodes one per line.
# return:
sub add_note_API( $ )
{
	my $patronFile = $TEMP_DIR."/patron.flat";
	my $patronTMP  = shift;
	my $noteField = $opt{'m'};
	my $patronModifiedFile = $TEMP_DIR."/patron_mod.flat";
	`cat "$patronTMP" | seluser -iB -oU | dumpflatuser >$patronFile`;
		
	# Update the user's account. Now it turns out that on the recommendation of Margaret Pelfrey 
	# you need get the entire record from dumpflatuser, modify the contents, and overlay the record
	# over the original.
	# 1) zero out the email. Now we have to remove the record not just empty it.
	# `echo "$barCode||" | edituserved -b -eEMAIL -l"ADMIN|PCGUI-DISP" -t1`;
	# 2) edit the note field to include previous notes and the requested message.
	
	# TODO: open and read the flat unmodified customer flat file.
	open PATRON, "<$patronFile" or die "Error reading '$patronFile': $!\n";
	open UPDATEPATRON, ">$patronModifiedFile" or die "Error creating '$patronModifiedFile': $!\n";
	while (<PATRON>)
	{
		my @VEDFields = split( '\n' );
		while ( @VEDFields )
		{
			my $VEDField = shift( @VEDFields );
			if ( $VEDField =~ m/^\.USER_XINFO_BEGIN\./ )
			{
				print UPDATEPATRON "$VEDField\n";
				print UPDATEPATRON ".NOTE. |a$noteField\n";
			}
			else
			{
				print UPDATEPATRON "$VEDField\n";
			}
		}
	}
	close PATRON;
	close UPDATEPATRON;
	if ( $opt{'U'} )
	{
		# -aR replace address fields, -bR replace extended fields, -mu just update user never create, -n don't reference BRS
		# This switch is necessary so that the loadflatuser doesn't check for ACTIVE_IDs for the customer, then failing if they
		# have them. -n does create an entry in /s/sirsi/Unicorn/Database/Useredit, so touchkeys is not required.
		`cat "$patronModifiedFile" | loadflatuser -aR -bR -l"ADMIN|PCGUI-DISP" -mu -n`;
	}
}

# Adds a note via the SirsiDynix tool edituserved.
# param:  Input file name, barcodes one per line.
# return:
sub add_note_edituserved( $ )
{
	my $input_file = shift;
	my $message =  $opt{'m'};
	# echo "21221019003992|$message" | edituserved -c -l"ADMIN|PCGUI-DISP" -eNOTE -tx
	open BARCODES, "<$input_file" or die "Error creating '$input_file': $!\n";
	while (<BARCODES>)
	{
		my $user_id = $_;
		chomp $user_id;
		printf "echo \"$user_id|$message\" | edituserved -c -l\"$USER_ID|$STATION\" -eNOTE -tx\n";
		`echo "$user_id|$message" | edituserved -c -l"$USER_ID|$STATION" -eNOTE -tx`;
	}
	close BARCODES;
}

# Kicks off the setting of various switches.
# param:  
# return: 
sub init
{
    my $opt_string = 'm:qtUw:x';
    getopts( "$opt_string", \%opt ) or usage();
    usage() if ( $opt{'x'} );
	# Message must not be empty or just white space.
    if ( ! $opt{'m'} or $opt{'m'} =~ m/^\s+$/ )
	{
		print STDERR "**error you must have a message to put on these accounts.\n";
		usage();
	}
	printf STDERR "Deprecated operation, working dir set to '%s'\n", $TEMP_DIR if ( $opt{'w'} );
}

init();
my $results = '';
while (<>)
{
	$results .= $_;
}
my $user_barcodes = create_tmp_file( "addnote_00", $results );
if ( $opt{'q'} )
{
	add_note_edituserved( $user_barcodes );
}
else
{
	add_note_API( $user_barcodes );
}
if ( $opt{'t'} )
{
	printf STDERR "Temp files will not be deleted. Please clean up '%s' when done.\n", $TEMP_DIR;
}
else
{
	clean_up();
}
# EOF
