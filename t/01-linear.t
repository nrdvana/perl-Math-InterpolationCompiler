#! /usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Data::Dumper;
use Try::Tiny;

use_ok( 'Math::InterpolationCompiler' ) or BAIL_OUT;

sub is_near {
	my ($actual, $expected, $tolerance, $message)= @_;
	if (abs($actual - $expected) <= $tolerance) {
		main::pass $message;
	} else {
		main::fail $message;
		main::diag sprintf("    abs( %.4f - %.4f ) = %.4f > %.4f", $actual, $expected, ($actual-$expected), $tolerance);
	}
}

my @tests= (
	# simple line, slope = 1
	{ name => '2-point line',
	  points => [ [0,0], [1,1] ],
	  test => [ [-1,0], [-.5,0], [0,0], [.1,.1], [.15,.15], [.9,.9], [1,1], [1.1,1], [999,1] ]
	},
	# line with dicontinuity at 1
	{ name => '2 segments with discontinuity',
	  points => [ [0,0], [1,.5], [1,1.5], [2,2] ],
	  test => [ [-1,0], [0,0], [.9,.45], [1,1.5], [2,2] ]
	},
	# we sanitize input.  make sure this fails
	{ name => 'un-clean input',
	  points => [ [0,'$$'], [1,.5] ],
	  exception => qr/not a number/i,
	},
	# domain should be sorted.  exception otherwise
	{ name => 'un-sorted domain',
	  points => [ [0,1], [1,2], [0.5,1] ],
	  exception => qr/domain.*sorted/i,
	},
);

for my $interp (@tests) {
	subtest 'linear( '.$interp->{name}.' )' => sub {
		my ($interpolation, $err);
		try {
			$interpolation= Math::InterpolationCompiler->new(
				points => $interp->{points},
				defined $interp->{algorithm}? (algorithm => $interp->{algorithm}) : (),
				defined $interp->{domain_edge}? (domain_edge => $interp->{domain_edge}) : (),
			);
			my $fn= $interpolation->fn;
			for (@{ $interp->{test} }) {
				is_near( $fn->( $_->[0] ), $_->[1], .000001, 'fn('.$_->[0].')' )
					or diag $interpolation->perl_code;
			}
			if ($interp->{exception}) {
				fail "Didn't get exception $interp->{exception}";
			}
		}
		catch {
			chomp(my $err= $_);
			if (!$interp->{exception} || !($err =~ $interp->{exception})) {
				fail "Unexpected exception '$err'";
			}
			else {
				pass "Got matching exception";
			}
		};
		done_testing;
	};
}

done_testing;
