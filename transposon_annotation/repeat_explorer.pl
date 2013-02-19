#!/usr/bin/env perl

use strict;
use warnings;
use autodie qw(open);
use Getopt::Long;
use Storable qw(freeze thaw);
use feature 'say';
use lib qw(/home/jmblab/statonse/apps/perlmod/Capture-Tiny-0.19/blib/lib);
use Capture::Tiny qw(:all);
use File::Basename;
use List::Util qw(max);

my $infile;
my $outfile;
my $percent_id;
my $percent_coverage;
my $cluster_file;
my $usage = "USAGE: $0 -i inreport -o hitsort -id 90.00 -cov 0.50 -cls clusterfile\n";

my %match_pairs;
my %match_index;

#counters
my $total_hits = 0;
my $parsed_hits = 0;
my $index = 0;

GetOptions(
           'i|infile=s'         => \$infile,
           'o|outfile=s'        => \$outfile,
	   'id|percent_id=f'    => \$percent_id,
	   'cov|percent_cov=f'  => \$percent_coverage,
	   'cls|cluster_file=s' => \$cluster_file,
          );

# open the infile or die with a usage statement
print $usage and exit(1) if !$infile or !$outfile or !$cluster_file or !$percent_id or !$percent_coverage;

open(my $in, '<', $infile);

while (<$in>) { 
    chomp; 
    my ($q_name, $q_len, $q_start, $q_end, $s_name, $s_len, 
	$s_start, $s_end, $pid, $score, $e_val, $strand) = split;
    
    my $pair = join "|", $q_name, $s_name;
    my $revpair = join "|", $q_name, $s_name;
    my $subj_hit_length = ($s_end - $s_start) + 1;
    my $subj_cov = $subj_hit_length/$s_len;
    
    if ($strand eq '-') {
	$total_hits++;
	my $neg_query_hit_length = ($q_start - $q_end) + 1;
	my $neg_query_cov = $neg_query_hit_length/$q_len;
	
	if ( ($neg_query_cov >= $percent_coverage) && ($subj_cov >= $percent_coverage) && ($pid >= $percent_id) ) {
	    if (exists $match_pairs{$pair}) {
		push @{$match_pairs{$pair}}, $score;
	    }
	    else {
		$match_pairs{$pair} = [$score];
		$match_index{$q_name} = [] unless exists $match_index{$q_name}; # hash is much more memory efficient 1.6g v 2.3g
		$match_index{$s_name} = [] unless exists $match_index{$s_name}; # though only ~1s faster
	    }
	}
    }
    else {
	$total_hits++;
	my $pos_query_hit_length = ($q_end - $q_start) + 1;
	my $pos_query_cov = $pos_query_hit_length/$q_len;
	
	if ( ($pos_query_cov >= $percent_coverage) && ($subj_cov >= $percent_coverage) && ($pid >= $percent_id) ) {
	    if (exists $match_pairs{$pair}) {
		push @{$match_pairs{$pair}}, $score;
	    }
	    else {
		$match_pairs{$pair} = [$score];
		$match_index{$q_name} = [] unless exists $match_index{$q_name};
		$match_index{$s_name} = [] unless exists $match_index{$s_name};
	    }
	}
    }
}
close($in);

my $index_file = $outfile.".index";
open(my $out, '>', $outfile);
open(my $indexout, '>', $index_file);

for my $id (keys %match_index) {
    $match_index{$id} = $index; 
    say $indexout "$id $index";
    #$id_index{$index} = $id;
    $index++; 
}
close($indexout);

for my $match (keys %match_pairs) {
    my $match_score = max(@{$match_pairs{$match}});
    $parsed_hits++;
    next unless defined $match_score;
    my ($qry, $sbj) = split /\|/, $match;
    if (exists $match_index{$qry} && exists $match_index{$sbj}) {
	say $out join "\t", $match_index{$qry}, $match_index{$sbj}, $match_score;
    }
}
close($out);

my $community = louvain_method($outfile, $index_file);
make_clusters($community, \%match_index, $cluster_file);

#my $sindex = freeze \%match_index;
#
# Subs
#
sub louvain_method {
    my ($cls_int, $index_file) = @_;
    my ($iname, $ipath, $isuffix) = fileparse($cls_int, qr/\.[^.]*/);
    my $cls_bin = $iname.".bin";
    my $cls_tree = $iname.".tree";
    my $cls_tree_weights = $cls_tree.".weights";
    my $cls_tree_log = $cls_tree.".log";
    my $hierarchy_err = $cls_tree.".hierarchy.log";
    system("louvain_convert -i $cls_int -o $cls_bin -w $cls_tree_weights");
    system("louvain_community $cls_bin -l -1 -w $cls_tree_weights -v >$cls_tree 2>$cls_tree_log");

    my $levels = `grep -c level $cls_tree_log`;
    chomp($levels);

    my @comm;

    for (my $i = 0; $i <= $levels-1; $i++) {
        my $cls_graph_comm = $cls_tree.".graph_node2comm_level_".$i;
	my $cls_graph_clusters = $cls_tree.".graph.clusters";
	my $cls_graph_membership = $cls_tree.".graph.membership";

        system("louvain_hierarchy $cls_tree -l $i > $cls_graph_comm");

        #system("~/apps/repeatexplorer/umbr_programs/seqclust/programs/makeCls.py $cls_graph_comm $index_file cls_graph_clusters_makeCls cls_graph_membership_makeCls");
	push @comm, $cls_graph_comm;
    }
    return \@comm;
}

sub make_clusters {
    my ($graph_comm, $match_index, $cluster_file) = @_;

    my @graph_comm_sort = reverse sort { ($a =~ /(\d)$/) <=> ($b =~ /(\d)$/) } @$graph_comm;
    my $graph = shift @graph_comm_sort;
    my %rindex = reverse %$match_index;
    my %clus;

    my $membership_file = $cluster_file.".membership.txt";
    open(my $mem,'>', $membership_file);
    open(my $in, '<', $graph);
    open(my $cls_out, '>', $cluster_file);

    while (my $line = <$in>) {
	chomp $line;
	my ($i, $j) = split /\s/, $line;
	if (exists $clus{$j}) {
	    push @{$clus{$j}}, $i;
	}
	else {
	    $clus{$j} = [$i];
	}
    }
    close($in);

    my $cls_ct = 1;
    for my $cls (reverse sort { @{$clus{$a}} <=> @{$clus{$b}} } keys %clus) {
	my $clus_size = scalar @{$clus{$cls}};
	say $cls_out ">CL$cls_ct $clus_size";
	#say "$cls_ct has $clus_size members";
	my @clus_members;
	for my $cls_member (@{$clus{$cls}}) {
	    say $mem "$cls_member $cls_ct";
	    if (exists $rindex{$cls_member}) {
		push @clus_members, $rindex{$cls_member};
	    }
	}
	say $cls_out join " ", @clus_members;
	$cls_ct++;
    }
    close($cls_out);
    close($mem);
    # output CLS for each level and clusterMembership.txt for each level
}


