package Math::InterpolationCompiler;
use Moo;
use Types::Standard 'ArrayRef';
use Carp;

# ABSTRACT: Compile interpolations into perl coderefs

=head1 SYNOPSIS

  my $fn= Math::InterpolationCompiler->new(
    domain      => [ 1, 2, 3, 4, 5 ],
    range       => [ 1.9, 1.3, 1.2, 1.1, 1.05 ],
    algorithm   => 'linear',
    domain_edge => 'die',
  )->fn;
  print $fn->(3);   # 1.2
  print $fn->(3.5); # 1.15

=head1 DESCRIPTION

This module is much the same theme as L<Math::Interpolate> and
L<Math::Interpolator::Linear> but it compiles the linear interpolations into
actual Perl code, and pre-calculates all the numbers so that the end result is
Log_base2(N) comparisons and a multiply and an add.
This makes it very fast for repeated calls.

Use this module if you have a few smallish data plots which you want to
evaluate very quickly over and over again.

DO NOT use this module if you have an extremely large data array that changes
frequently, if your data points are not plain scalars, or if you are extremely
worried about code-injection attacks.
(this module sanitizes the numbers you give it, but it is still generating
perl code and in security-critical environments with un-trusted input your
best bet is to just avoid all string-evals).

This generator is written as a Perl object which produces a coderef.  This
makes the generator easy to extend and re-use pieces for various goals.
However the OO design is really just a convenient way of calling one
complicated function with lots of argument varieties.

=head1 ATTRIBUTES

=head2 domain

The input values ('x') of the function.
Domain must be sorted in non-decreasing order.

=head2 range

The output values ('y') of the function.

=head2 algorithm

The name of the algorithm to create:

=over

=item linear

Create a linear interpolation, where an input ('x') is matched to the interval
containing that value, and the return value is

  y = x * (y_next - y_prev) / (x_next - x_prev)

If a zero-width range is encountered (a discontinuity in the line) the 'x'
values less than the discontinuity use the left-hand segment, and the 'x'
values equal to or to the right of the discontinuity use the right-hand
segment.

Example:

  # domain => [ 1, 2, 2, 3 ],
  # range  => [ 0, 0, 1, 1 ],
  $fn->(1);   # equals 0
  $fn->(1.9); # equals 0
  $fn->(2);   # equals 1
  #fn->(3);   # equals 1

=back

=head2 domain_edge

The behavior of the generated function when an input value ('x') lies outside
the domain of the function.

=over

=item clamp

If 'x' is less than the minimum valid 'x', use the minimum 'x'.
If 'x' is greater than the maximum valid 'x', use the maximum 'x'.

=item extrapolate

If 'x' is less than the minimum valid 'x', extrapolate backwards from the
first non-empty interval.  If 'x' is greater than the maximum valid 'x',
extrapolate forward from the last non-empty interval.

=item undef

Return undef for any 'x' outside the domain for the function.

=item die

Die with an error for any 'x' outside of the domain for the function.

=back

=head2 perl_code

Lazy-build the perl code for this function using the other attributes.
Returns a string of perl code.

=head2 fn

Lazy-build the perl coderef for the L<perl_code> attribute.

=head2 sanitize

Boolean.  Whether or not to sanitize the domain and range with a 'number'
regex during the constructor.  Defaults to true.

Setting this to false leaves you open to code injection attacks, but you might
choose to do that if you trust your input and you need a little performance
boost on constructing this object.

=head1 METHODS

=head2 new

Standard object constructor accepting any of the above attributes, but also
accepting:

=over

=item points

  ->new( points => [ [1,1], [2,2], [3,2], ... ] );

For convenience, you can specify your domain and range as an arrayref of (x,y)
pairs.  During BUILDARGS, this will get separated into the domain and range
attributes.

=back

=cut

has domain       => ( is => 'ro', isa => ArrayRef, required => 1 );
has range        => ( is => 'ro', isa => ArrayRef, required => 1 );
has algorithm    => ( is => 'ro', default => sub { 'linear' } );
has domain_edge  => ( is => 'ro', default => sub { 'clamp' } );
has perl_code    => ( is => 'lazy' );
has fn           => ( is => 'lazy' );
has sanitize     => ( is => 'ro', default => sub { 1 } );

sub BUILDARGS {
	my $self= shift;
	my $args= $self->next::method(@_);
	if ($args->{points} && !$args->{domain} && !$args->{range}) {
		my (@domain, @range);
		for (@{ delete $args->{points} }) {
			push @domain, $_->[0];
			push @range,  $_->[1];
		}
		$args->{domain}= \@domain;
		$args->{range}=  \@range;
	}
	return $args;
}

sub _validate_number {
	$_[0]= "$_[0]";
	$_[0] =~ /^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$/
		or croak "$_[0] is not a number";
}

sub BUILD {
	my $self= shift;
	@{ $self->domain } == @{ $self->range }
		or croak "Domain and range differ in length (".@{ $self->domain }." != ".@{ $self->range }.")";
	@{ $self->domain } > 1
		or croak "Domain does not contain any intervals";
	my $prev;
	my $sanitize= $self->sanitize;
	for (@{ $self->domain }) {
		_validate_number($_) if $sanitize;
		croak "Domain is not sorted in non-decreasing order"
			if defined $prev && $_ < $prev;
		$prev= $_;
	}
	if ($sanitize) {
		_validate_number($_) for @{ $self->range };
	}
	$self->can("_gen_".$self->algorithm)
		or croak "Unknown algorithm ".$self->algorithm;
}

sub _build_perl_code {
	my $self= shift;
	my $method= $self->can("_gen_".$self->algorithm);
	return $self->$method;
}

sub _build_fn {
	my $self= shift;
	my $sub= eval $self->perl_code
		or croak "Failed to build function: $@";
	return $sub;
}

# Create a linear interpolation
sub _gen_linear {
	my $self= shift;
	my $domain= $self->domain;
	my $range= $self->range;
	my @expressions;
	for (my $i= 1; $i < @$domain; $i++) {
		# skip discontinuities
		next if $domain->[$i] == $domain->[$i-1];
		# calculate slope and offset at x0
		my $m= ($range->[$i] - $range->[$i-1]) / ($domain->[$i] - $domain->[$i-1]);
		my $b= $range->[$i-1] - $domain->[$i-1] * $m;
		# generate code
		push @expressions, [ $domain->[$i-1], '$x * '.$m.' + '.$b ];
	}
	if ($self->domain_edge eq 'clamp') {
		unshift @expressions, [ undef, $domain->[0] ];
		push    @expressions, [ $domain->[-1], $domain->[-1] ];
	}
	elsif ($self->domain_edge eq 'extrapolate') {
		# just let the edge expressions do their thing
	}
	elsif ($self->domain_edge eq 'undef') {
		unshift @expressions, [ undef, 'undef' ];
		push    @expressions, [ $domain->[-1], '$x == '.$domain->[-1].'? ('.$range->[-1].') : undef' ];
	}
	elsif ($self->domain_edge eq 'die') {
		unshift @expressions, [ undef, 'die "argument out of bounds (<'.$domain->[0].')"' ];
		push    @expressions, [ $domain->[-1], '$x == '.$domain->[-1].'? ('.$range->[-1].') : die "argument out of bounds (>'.$domain->[-1].')"' ];
	}
	else {
		croak "Algorithm 'linear' does not support domain-edge '".$self->domain_edge."'";
	}
	# Now tree-up the expressions
	while (@expressions > 1) {
		my ($i, $dest);
		for ($i= 1, $dest= 0; $i < @expressions; $i+= 2) {
			$expressions[$dest++]= [
				$expressions[$i-1][0],
				'$x < '.$expressions[$i][0]."?"
				.' ('.$expressions[$i-1][1].")"
				.':('.$expressions[$i][1].")"
			];
		}
		# odd number?
		if ($i == @expressions) {
			$expressions[$dest++]= $expressions[-1];
		}
		# truncate list
		$#expressions= $dest-1;
	}
	# finally, wrap with function
	return "sub {\n my \$x= shift;\n return ".$expressions[0][1].";\n}\n";
}

1;
