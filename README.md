Mon Nov 17 14:54:31 MST 2014
----------------------------

Project Notes
-------------
This script was developed to cope with reciprocal borrowers. We have thousands, and we 
want to add a note on all of their accounts to ask staff to change their accounts to 
EPL-METRO. What ever your requirement, if you need to put a note on a lot of accounts
this is the script for you. While edituserved will do the same job, this script has 
the advantage that you just need all the user ids, not ids and notes pipe separated.
Your choice.

Neither method of adding notes affects the last activity date of the the customer.

Note
-----
```
-w DEPRECATED
```

It does not remove notes, merely adds a new one.

Instructions for Running
------------------------
```
cat user_barcodes.lst | addnote.pl -m"Message for note field." -U
echo 21221019003992 | addnote.pl -m"Added note the new way" -q
```

Product Description
-------------------
Perl script written by Andrew Nisbet for Edmonton Public Library, distributable by the enclosed license.

Repository Information
----------------------
This product is under version control using Git.

Dependencies
------------
edituserved

Known Issues
------------
None
