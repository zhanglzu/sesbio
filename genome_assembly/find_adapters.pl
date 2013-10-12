#!/usr/bin/env perl

# TODO: make the threshold an option

use 5.010;
use strict;
use warnings;
use File::Basename;
use Getopt::Long;
use Data::Dumper;
BEGIN {
  @AnyDBM_File::ISA = qw( DB_File SQLite_File )
      unless @AnyDBM_File::ISA == 1; # if loaded already, AnyDBM_File::ISA has a length of one;
}
use AnyDBM_File;
use vars qw( $DB_BTREE &R_DUP );
use AnyDBM_File::Importer qw(:bdb);

#
# lexical vars
#
my $infile;
my $five_prime_outfile;
my $three_prime_outfile;
my $threshold;

GetOptions(
           'i|infile=s'                   => \$infile,
           'a|five_prime_outfile=s'       => \$five_prime_outfile,
	   'b|three_prime_outfile=s'      => \$three_prime_outfile,
           't|threshold=i'                => \$threshold,
           );

#
# Check @ARGV
# TODO: Add POD and other useful options (help, man)
#usage() and exit(0) if $help;

#pod2usage( -verbose => 2 ) if $man;

if (!$infile  || !$five_prime_outfile || !$three_prime_outfile) {
    print "\nERROR: Command line not parsed correctly. Check input.\n\n";
    usage();
    exit(1);
}

open my $in, '<', $infile or die "ERROR: Could not open file: $infile\n";
open my $fout, '>', $five_prime_outfile or die "ERROR: Could not open file: $five_prime_outfile\n";
open my $rout, '>', $three_prime_outfile or die "ERROR: Could not open file: $three_prime_outfile\n";

my (%rseqhash, %fseqhash);
$DB_BTREE->{cachesize} = 100000;
$DB_BTREE->{flags} = R_DUP;
tie( %rseqhash, 'AnyDBM_File', ':memory:', 0666, $DB_BTREE);
tie( %fseqhash, 'AnyDBM_File', ':memory:', 0666, $DB_BTREE);


my @aux = undef;
my ($name, $seq, $qual);
$threshold //= 100;

while (($name, $seq, $qual) = readfq(\*$in, \@aux)) {
    my $radapter = substr($seq, -25, 25);
    my $fadapter = substr($seq, 0, 25);
    $rseqhash{$radapter}++;
    $fseqhash{$fadapter}++;        
}

for my $fkey (reverse sort { $fseqhash{$a} <=> $fseqhash{$b} } keys %fseqhash) {
    if ($fseqhash{$fkey} > $threshold) {
	say $fout join "\t", $fkey, $fseqhash{$fkey};
    }
}
for my $rkey (reverse sort { $rseqhash{$a} <=> $rseqhash{$b} } keys %rseqhash) {
    if ($rseqhash{$rkey} > $threshold) {
	say $rout join "\t", $rkey, $rseqhash{$rkey};
    }
}
close $fout;
close $rout;

untie %fseqhash;
untie %rseqhash;

exit;
#
# Subs
#
sub readfq {
    my ($fh, $aux) = @_;
    @$aux = [undef, 0] if (!defined(@$aux));
    return if ($aux->[1]);
    if (!defined($aux->[0])) {
        while (<$fh>) {
            chomp;
            if (substr($_, 0, 1) eq '>' || substr($_, 0, 1) eq '@') {
                $aux->[0] = $_;
                last;
            }
        }
        if (!defined($aux->[0])) {
            $aux->[1] = 1;
            return;
        }
    }
    ################################ SES mod 5/17/12
    my $name;
    if (/^.?(\S+\s\S+)/) {          # Illumina 1.8+
	$name = $1;
    }
    elsif (/^.?(\S+)/) {            # Illumina 1.3+
	$name = $1;
    } else {
	$name = '';                 # ?
    }
    #my $name = /^.(\S+)/? $1 : ''; # Heng Li's original regex
    ################################
    my $seq = '';
    my $c;
    $aux->[0] = undef;
    while (<$fh>) {
        chomp;
        $c = substr($_, 0, 1);
        last if ($c eq '>' || $c eq '@' || $c eq '+');
        $seq .= $_;
    }
    $aux->[0] = $_;
    $aux->[1] = 1 if (!defined($aux->[0]));
    return ($name, $seq) if ($c ne '+');
    my $qual = '';
    while (<$fh>) {
        chomp;
        $qual .= $_;
        if (length($qual) >= length($seq)) {
            $aux->[0] = undef;
            return ($name, $seq, $qual);
        }
    }
    $aux->[1] = 1;
    return ($name, $seq);
}

sub usage {
    my $script = basename($0);
    print STDERR<<EOF
USAGE: $script [-i] [-a] [-b] [-t]  [-h] [-m]

Required:
    -i|infile               :       File of reads (Fasta for Fastq format).
    -a|five_prime_outfile   :       Name of file to write the five prime adapter counts.
    -b|three_prime_outfile  :       Name of file to write the three prime adapter counts.
    
Options:
    -t|threshold            :       Set the lower threshold of counts for matches to report (Default: 100).
    -h|help                 :       Print a usage statement.
    -m|man                  :       Print the full documentation.

EOF
}