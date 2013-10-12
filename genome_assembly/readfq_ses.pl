package readfq_ses;

use 5.014;
use Moose;
use namespace::autoclean;

with 'File';

has 'id' => (
    is        => 'rw',
    isa       => 'Str',
    reader    => 'get_id',
    writer    => 'set_id',
    predicate => 'has_id',
    );

has 'seq' => (
    is        => 'rw',
    isa       => 'Str',
    reader    => 'get_seq',
    writer    => 'set_seq',
    predicate => 'has_seq',
    );

has 'qual' => (
    is        => 'rw',
    lazy      => 1,
    default   => undef,
    reader    => 'get_qual',
    writer    => 'set_qual',
    predicate => 'has_qual',
    );

sub next_seq {
    my ($self, $fh) = @_;

    my $line = <$fh>;
    return unless defined $line;
    chomp $line;

    my (@seqs, @quals);
    if (substr($line, 0, 1) eq '>') {
	my $name = _set_id_per_encoding($line);
	$self->set_id($name);
        
	my $sline = <$fh>;
	chomp $sline;

	my $seqline;
	if ($sline =~ /[ATCGNatcgn]/) {
	    push @seqs, $sline;
	    while ($seqline = <$fh>) {
		last if $seqline =~ />/;
		push @seqs, $seqline;
	    }
	}
	seek $fh, -length($seqline), 1 if length $seqline;
	my $seq = join '', @seqs;
	$seq =~ s/>.*// if $seq =~ />/;
	$seq =~ s/\s//g;
	#say $seq;
	$self->set_seq($seq);

	return $self;
    }
    if (substr($line, 0, 1) eq '@') {
	my $name = _set_id_per_encoding($line);
	my $id = $1 if $line =~ /^@(\w+|\d+)(?::|-)/;
	my $pat = qr/$id/;
	$self->set_id($name);

	my $sline = <$fh>;
        chomp $sline;

        my $seqline;
        if ($sline =~ /[ATCGNatcgn]/) {
            push @seqs, $sline;
            while ($seqline = <$fh>) {
                last if $seqline =~ /\+/;
                push @seqs, $seqline;
            }
        }
	seek $fh, -length($seqline), 1 if length $seqline;
	my $seq = join '', @seqs;
        $seq =~ s/\+.*// if $seq =~ /\+/;
        $seq =~ s/\s//g;
        $self->set_seq($seq);

	
	my $cline = <$fh>;
	my $qline;
	while ($qline = <$fh>) {
	    chomp $qline;
	    last if $qline =~ /$pat/;
	    push @quals, $qline;
	}
	seek $fh, -length($qline)-1, 1 if length $qline;
	my $qual = join '', @quals;
        $qual =~ s/${pat}.*// if $qual =~ /${pat}/;
        $qual =~ s/\s//g;
	$self->set_qual($qual);

	return $self;
    }
}

sub _set_id_per_encoding {
    my $hline = shift;
    if ($hline =~ /^.?(\S+)\s(\d)\S+/) {
        return $1."/".$2;
    }
    elsif ($hline =~ /^.?(\S+)/) {
        return $1;
    }
    else {
        return '';
    }
}

__PACKAGE__->meta->make_immutable;

package main;

use 5.014;
use strict;
use warnings;
use autodie qw(open);
use Data::Dump qw(dd);

my $usage = "$0 infile\n";
my $infile = shift or die $usage;

my $seqio = readfq_ses->new( file => $infile );
my $fh = $seqio->get_fh;

while (my $seq = $seqio->next_seq($fh)) {
    if ($seq->has_qual) {
	say join "\n", "@".$seq->get_id, $seq->get_seq, '+', $seq->get_qual;
    }
    else {
	say join "\n", ">".$seq->get_id, $seq->get_seq;
    }
}