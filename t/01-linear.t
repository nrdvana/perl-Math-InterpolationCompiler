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
	# extrapolate off the end of the last line
	{ name => 'extrapolate',
	  points => [ [1,1], [2,1], [3,0] ],
	  domain_edge => 'extrapolate',
	  test => [ [0,1], [-1000,1], [1,1], [2,1], [3,0], [4,-1], [5,-2], [1000,-997] ],
	},
	# return undef outside of the domain
	{ name => 'undef outside domain',
	  points => [ [5,1], [5,2], [6,2], [6,1] ],
	  domain_edge => 'undef',
	  test => [ [4.9999, undef], [5,2], [6,1], [6.0001, undef] ],
	},
	# error on invalid domain
	{ name => 'undef outside domain',
	  points => [ [5,1], [5,2], [6,2], [6,1] ],
	  domain_edge => 'die',
	  test => [ [4.9999, undef] ],
	  exception => qr/bounds.*<5/
	},
	# error on invalid domain
	{ name => 'undef outside domain',
	  points => [ [5,1], [5,2], [6,2], [6,1] ],
	  domain_edge => 'die',
	  test => [ [5,2], [6,1], [6.0001, undef] ],
	  exception => qr/bounds.*>6/
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
				my $y= $fn->( $_->[0] );
				if (defined $y && defined $_->[1]) {
					is_near( $y, $_->[1], .000001, 'fn('.$_->[0].')' )
						or diag $interpolation->perl_code;
				} else {
					is( $y, $_->[1], 'fn('.$_->[0].')' );
				}
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
