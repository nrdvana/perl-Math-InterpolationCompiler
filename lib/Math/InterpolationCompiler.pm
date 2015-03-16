package Math::InterpolationCompiler;
use Moo;
use Types::Standard 'ArrayRef';
use Carp;

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

#  0000  ( 1, 25.5 )     low_end_behavior
#  0001  ( 1.5, 33.2 )   $x > 1? (y=x*m0+b0) : solve(0000)
#  0010  ( 2, 34.4 )     (y=x*m1+b1)
#  0011  ( 2.5, 55 )     $x > 2? (y=x*m2+b2) : solve(0010)
#  0100  ( 3, 9 )
#  0101                  high_end_behavior
#
#  code(0) = ( low_end_behavior )
#  code(1) = ( $x < 1? code(0) : 

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
		unshift @expressions, [ undef, ''.$domain->[0] ];
		push    @expressions, [ $domain->[-1], ''.$domain->[-1] ];
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
