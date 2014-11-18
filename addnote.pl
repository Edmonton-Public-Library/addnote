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
my $VERSION   = qq{0.3};
my $WORK_DIR  = qq{/tmp};

#
# Message about this program and how to use it.
#
sub usage()
{
    print STDERR << "EOF";

	usage: $0 [-xU] [-m"Message string"]
addnote.pl reads customer account barcodes on STDIN and adds 
a message to the note field of each account if it exists.

 -m<message>: REQUIRED. Message for the note field. The message will be tested to 
              ensure it is not empty. Do not use '!' or other special characters in message.
 -U         : Actually do the updates to the account, otherwise
              just creates the flat user overlay file.
 -w<work/dir>: The working directory '/tmp' by default.
 -x         : This (help) message.

example: $0 -x
Version: $VERSION
EOF
    exit;
}

# Kicks off the setting of various switches.
# param:  
# return: 
sub init
{
    my $opt_string = 'm:Uw:x';
    getopts( "$opt_string", \%opt ) or usage();
    usage() if ( $opt{'x'} );
	# Message must not be empty or just white space.
    if ( ! $opt{'m'} or $opt{'m'} =~ m/^\s*$/ )
	{
		print STDERR "**error you must have a message to put on these accounts.\n";
		usage();
	}
	if ( $opt{'w'} )
	{
		if ( -d $opt{'w'} )
		{
			$WORK_DIR = $opt{'w'};
			print STDERR "working dir set to $WORK_DIR\n";
		}
		else
		{
			print STDERR "**error the directory specified with '-w' does not exist.".$opt{'w'}."\n";
			usage();
		}
	}
}

init();
my $patronFile = $WORK_DIR."/patron.flat";
my $patronTMP  = $WORK_DIR . "/patron.tmp";
open TMP_PATRON, ">$patronTMP" or die "Error writing tmp '$patronTMP': $!\n";
while (<>)
{
	print TMP_PATRON;
}
close TMP_PATRON;
`cat "$patronTMP" | seluser -iB -oU | dumpflatuser >$patronFile`;
	
# Update the user's account. Now it turns out that on the recommendation of Margaret Pelfrey 
# you need get the entire record from dumpflatuser, modify the contents, and overlay the record
# over the original.
# 1) zero out the email. Now we have to remove the record not just empty it.
# `echo "$barCode||" | edituserved -b -eEMAIL -l"ADMIN|PCGUI-DISP" -t1`;
# 2) edit the note field to include previous notes and the requested message.

my $noteField = $opt{'m'};
my $patronModifiedFile = $WORK_DIR."/patron_mod.flat";
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
# EOF
