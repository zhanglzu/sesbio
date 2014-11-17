#!/usr/bin/env perl

## Given an epithet, this script will build the taxonomic lineage using
## NCBI's EUtilities (esearch and efetch)

## TODO: Build lineage info based on....(the number of entries?). It is not so
## simple for all species because of naming schemes in different kingdoms.

use 5.010;
use strict;
use warnings;
use HTTP::Tiny;
use XML::LibXML;

my $id      = 4232; # Helianthus annuus
my $genus   = 'Helianthus';
my $species = 'annuus';

search_by_name($genus, $species);

#
# methods
#
sub search_by_name {
    my ($genus, $species) = @_;

    my $id = _fetch_id_for_name($genus, $species);
    say join "\t", $genus, $species, $id;
    
    _get_lineage_for_id($id);
}

sub _get_lineage_for_id {
    my ($id) = @_;
    my $esumm = "esumm_$id.xml"; 
 
    my $urlbase  = "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=taxonomy&id=$id";
    my $response = HTTP::Tiny->new->get($urlbase);

    unless ($response->{success}) {
        die "Can't get url $urlbase -- Status: ", $response->{status}, " -- Reason: ", $response->{reason};
    }

    open my $out, '>', $esumm or die "\nERROR: Could not open file: $!\n";
    say $out $response->{content};
    close $out;

    my $parser = XML::LibXML->new;
    my $doc    = $parser->parse_file($esumm);
    
    for my $node ( $doc->findnodes('//TaxaSet/Taxon') ) {
	my ($lineage) = $node->findvalue('Lineage/text()');
	my ($family)  = map  { s/\;$//; $_; }
	                grep { /(\w+aceae)/ } 
                        map  { split /\s+/  } $lineage;
	say "Family: $family";
	say "Full taxonomic lineage: $lineage";
    }
    
    unlink $esumm;
}

sub _fetch_id_for_name {
    my ($genus, $species) = @_;

    my $esearch  = "esearch_$genus"."_"."$species.xml";
    my $urlbase  = "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=taxonomy&term=$genus%20$species";
    my $response = HTTP::Tiny->new->get($urlbase);

    unless ($response->{success}) {
        die "Can't get url $urlbase -- Status: ", $response->{status}, " -- Reason: ", $response->{reason};
    }

    open my $out, '>', $esearch or die "\nERROR: Could not open file: $!\n";
    say $out $response->{content};
    close $out;

    my $id;
    my $parser = XML::LibXML->new;
    my $doc    = $parser->parse_file($esearch);
    
    for my $node ( $doc->findnodes('//eSearchResult/IdList') ) {
	($id) = $node->findvalue('Id/text()');
    }
    
    #unlink $esearch;
    
    return $id;
}
