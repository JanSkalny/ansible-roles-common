#! /usr/bin/perl -w
use strict;

use Digest::SHA;
use MIME::Base64;

print "Input new password: ";
system('stty','-echo');
#chop($password=<STDIN>);
my $pass = <>;
print "\nInput password again: ";
my $pass2 = <>;
system('stty','echo');
print "\n";
my $salt = join '', ('.', '/', 0..9, 'A'..'Z', 'a'..'z')[rand 64, rand 64, rand 64, rand 64 ];

$pass =~ s/\s+$//;
$pass2 =~ s/\s+$//;

die if ($pass ne $pass2);

#print "Salt is: $salt\n";

my $ctx = Digest::SHA->new;
$ctx->add($pass);
$ctx->add($salt);
print "{SSHA}";
print encode_base64($ctx->digest . $salt ,'')."\n";

