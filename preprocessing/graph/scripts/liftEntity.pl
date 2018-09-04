#!/usr/bin/perl

use FindBin;
use lib "$FindBin::Bin/../../misc";
use lib "$FindBin::Bin";
use simple;
use util;

# people terms that can also be objects (i.e., baseball pitcher
# vs. pitcher of water) The lexicon should have entries for the people
# version, so do not use the lexicon on these terms unless they are
# subjects (assuming that subjects are people, and non-subjects are not).
%psubj = ();
$psubj{"batter"} = 1;
$psubj{"diner"} = 1;
$psubj{"pitcher"} = 1;
$psubj{"speaker"} = 1;

# load the list of subjects so we know when to use the lexicon on the
# above terms.
%subj = ();
open(file, $ARGV[3]);
while (<file>) {
	chomp($_);
	@ax = split(/\t/, $_);
	$subj{$ax[1]} = 1;
}
close(file);

# if an age term is the first word of a multi-word head noun, we can
# drop that to form a more generic head noun.
%age = ();
$age{"adult"} = 1;
$age{"baby"} = 1;
$age{"child"} = 1;
$age{"teen"} = 1;
$age{"toddler"} = 1;

# $ARGV[1] is the corpus specific lexicon (and may not exist)
# $ARGV[2] is the default lexicon "../data/lexicon.txt"
unless (-e $ARGV[1]) {
	$ARGV[1] = $ARGV[2];
}

%lexicon = ();
open(file, $ARGV[1]);
while (<file>) {
	chomp($_);
	@ax = split(/\t/, $_);
	if (not exists $lexicon{$ax[0]}) {
		$lexicon{$ax[0]} = {};
	}
	$lexicon{$ax[0]}->{$ax[1]} = 1;
}
close(file);

@dep = ();
@X = ();
@Y = ();
@type = ();
$n = 0;
open(file, $ARGV[0]);
while (<file>) {
	chomp($_);
	@ax = split(/\t/, $_);
	if ($#ax == 1) {
		$ax[2] = "";
	}
	# read in a caption
	if ($#ax == 2) {
		@ay = split(/ /, $ax[2]);
		($next, $prev) = breakSlash(\@ay, 1);
		# Get the NPH of each NP in an EN chunk
		for ($i = 0; $i <= $#ay; $i += $next->[$i]) {
			if ($ay[$i]->[1] eq "[EN") {
				$enid = "$ax[0]#" . $ay[$i]->[2];
				for ($j = $i + 1; $next->[$j] != 0; $j += $next->[$j]) {
					if ($ay[$j]->[1] eq "[NP") {
						for ($k = $j + 1; $next->[$k] != 0; $k += $next->[$k]) {
							if ($ay[$k]->[1] eq "[NPH") {
								# @as/$s - head noun string
								# @ay/$t - head noun (including POS tags and indices)
								@as = ();
								@at = ();
								for ($l = 1; $l < ($next->[$k] - 1); $l++) {
									push(@as, $ay[$k + $l]->[1]);
									push(@at, join("/", @{$ay[$k + $l]}));
								}
								$s = join(" ", @as);
								$t = join(" ", @at);

								# check if we're dealing with a head
								# noun that has to be a subject before
								# we're certain it's a person (and
								# thus the actual meaning of the word
								# used in the lexicon)
								if (exists $psubj{$s} && !exists $subj{$enid}) {
									next;
								}

								# $changed is whether or not we've rewritten the NPH chunk
								# %visit is the set of strings we've already generated
								#   we use the string as the index, because when we're looking up
								#   if we've generated something or not, we don't care about the
								#   token IDs.  The value holds the actual string + metadata
								#   so that we can retrieve the token IDs, if needed.
								#   It also contains the set of rewrite rules we've already generated.
								# @queue is a queue of rewrite rules/transformations that we
								#   want to consider.  They're of the form <x>\t<y>, where
								#   <x> is the left side of the rewrite rule (more generic head)
								#   and <y> is the right side of the rewrite rule (more specific)
								$changed = 0;
								%visit = ();
								@queue = ();

								# we initialize by noting that we've visited the original string
								# in the NPH and we would like to generate rewrite rules for all
								# of the lexicon entries of that string.
								$visit{$s} = $t;
								if (exists $lexicon{$s}) {
									foreach (keys %{$lexicon{$s}}) {
										push(@queue, "$_\t$s");
									}
								}
								# additionally, if the first word is an age term, we can
								# go from the original string to the right most term.
								# primarily intended to go from "young boy" -> "boy", and the
								# like.  Due to the way the rewrite rules work, this doesn't
								# always work correctly.  (The rewrite rules assume a single
								# root head noun - this can violate that assumption.)
								@az = split(/ /, $s);
								if (exists $age{$az[0]} && $#az > 0) {
									$w = shift(@az);
									push(@queue, "$w\t$s");
#									push(@queue, join(" ", @az) . "\t$s");
								}

								# process the queue - generate the rewrite rule at the
								# top of the queue, add additional rewrite rules that can be
								# generated by the left side of the rewrite rule (more generic
								# term) to the queue
								foreach (@queue) {
									@az = split(/\t/, $_);

									$t = $az[0];
									$s = $az[1];
									# check if we've already generated this rewrite rule
									# note down that we are doing so if we haven't already.
									if (exists $visit{"$t\t$s"}) {
										next;
									}
									$visit{"$t\t$s"} = 1;

									# we've applied a rewrite rule - make sure we know we need
									# to rewrite the NPH chunk.
									$changed++;

									# if we've never seen the left hand side of the rewrite rule
									# we need to assign token IDs to the the new string.  Also,
									# all POS tags of the new string will be "NN".
									if (not exists $visit{$t}) {
										@t1 = ();
										foreach (split(/ /, $t)) {
											push(@t1, "$ax[1]/$_/NN");
											$ax[1]++;
										}
										$visit{$t} = join(" ", @t1);
									}

									# @t1 - sequence of token IDs of the left hand side of the rewrite rule
									@t1 = ();
									foreach (split(/ /, $visit{$t})) {
										@az = split(/\//, $_);
										push(@t1, $az[0])
										}
									$t1 = join(" ", @t1);
									
									addTransformation("", "$ay[$k]->[0] $t1 $ay[$k + $next->[$k] - 1]->[0]", "$ay[$k]->[0] $visit{$s} $ay[$k + $next->[$k] - 1]->[0]", "+NPHEAD/$s", \@dep, \@X, \@Y, \@type, \$n);

									# identify new rewrite rules buildable by the current
									# left hand side of the rewrite rule
									if (exists $lexicon{$t}) {
										foreach (keys %{$lexicon{$t}}) {
											push(@queue, "$_\t$t");
										}
									}
								}

								# if we've applied any rewrite rules, $t should be the most
								# generic head noun.  So replace the NPH chunk with that.
								if ($changed > 0) {
									@at = split(/ /, $visit{$t});
									breakSlash(\@at, 1);
									@ay = (@ay[0 .. $k], @at, @ay[$k + $next->[$k] - 1 .. $#ay]);
									($next, $prev) = getNextPrev(\@ay, 1);
								}
							}
						}
					}
				}
			}
		}
		printSentence($ax[0], $ax[1], \@ay, \@dep, \@X, \@Y, \@type, $n);

		@dep = ();
		@X = ();
		@Y = ();
		@type = ();
		$n = 0;
	# read in a rule, if the index matches ($n)
	} elsif ($#ax == 4) {
		if ($ax[0] == $n) {
			$dep[$ax[0]] = $ax[1];
			$X[$ax[0]] = $ax[2];
			$Y[$ax[0]] = $ax[3];
			$type[$ax[0]] = $ax[4];
			$n++;
		}
	}
}

close(file);
