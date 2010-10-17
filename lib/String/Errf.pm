use 5.12.0;
use warnings;
package String::Errf; # I really wanted to call it String::Fister.
use String::Formatter 0.102081 ();
use base 'String::Formatter';
# ABSTRACT: a simple sprintf-like dialect

use Scalar::Util ();

=head1 SYNOPSIS

  use String::Errf qw(errf);

  print errf "This process was started at %{start}t with %{args;argument}n.\n",
    { start => $^T, args => 0 + @ARGV };

...might print something like:

  This process was started at 2010-10-17 14:05:29 with 0 arguments.

=head1 DESCRIPTION

String::Errf provides C<errf>, a simple string formatter that works something
like C<L<sprintf|perlfunc/sprintf>>.  It is implemented using
L<String::Formatter> and L<Sub::Exporter>.  Their documentation may be useful
in understanding or extending String::Errf.

=head1 DIFFERENCES FROM SPRINTF

The data passed to C<errf> should be organized in a single hashref, not a list.

Formatting codes require named parameters, and the available codes are
different.  See L</FORMATTING CODES> below.

As with most String::Formatter formatters, C<%> is not a format code.  If you
want a literal C<%>, do not put anything between the two percent signs, just
write C<%%>.

=head2 FORMATTING CODES

C<errf> formatting codes I<require> a set of arguments between the C<%> and the
formatting code letter.  These arguments are placed in curly braces and
separated by semicolons.  The first argument is the name of the data to look
for in the format data.  For example, this is a valid use of C<errf>:

  errf "The current time in %{tz}s is %{now;local}t.", {
    tz  => $ENV{TZ},
    now => time,
  };

The second argument, if present, may be a compact form for multiple named
arguments.  The rest of the arguments will be named values in the form
C<name=value>.  The examples below should help clarify how arguments are
passed.  When an argument appears in both a compact and named form, the named
form trumps the compact form.

The specific codes and their arguments are:

=head3 i for integer

The C<i> format code is used for integers.  It takes one optional argument,
C<prefix>, which defaults to the empty string.  C<prefix> may be given as the
compact argument, standing alone.  C<prefix> is used to prefix non-negative
integers.  It may be a space or a plus sign.

  errf "%{x}i",    10; # returns "10"
  errf "%{x;+}i",  10; # returns "+10"
  errf "%{x; }i",  10; # returns " 10"
  errf "%{x; }i", -10; # returns "-10"

  errf "%{x;prefix=+}i",  10; # returns "+10"
  errf "%{x;prefix= }i",  10; # returns " 10"

The rounding behavior for non-integer values I<is not currently specified>.

=head3 f for float (or fractional)

The C<f> format code is for numbers with sub-integer precision.  It works just
like C<i>, but adds a C<precision> argument which specifies how many decimal
places of precision to display.  The compact argument may be just the prefix or
the prefix followed by a period followed by the precision.

  errf "%{x}f",     10.1234; # returns "10";
  errf "%{x;+}f",   10.1234; # returns "+10";
  errf "%{x; }f",   10.1234; # returns " 10";

  errf "%{x;.2}f",  10.1234; # returns  "10.12";
  errf "%{x;+.2}f", 10.1234; # returns "+10.12";
  errf "%{x; .2}f", 10.1234; # returns " 10.12";

  errf "%{x;precision=.2}f",          10.1234; # returns  "10.12";
  errf "%{x;prefix=+;precision=.2}f", 10.1234; # returns "+10.12";

=head3

=cut

use Carp ();
use Date::Format ();
use Params::Util ();

use Sub::Exporter -setup => {
  exports => {
    errf => sub {
      my ($class) = @_;
      my $fmt = $class->new;
      return sub { $fmt->format(@_) };
    },
  }
};

sub default_codes {
  return {
    i => '_format_int',
    f => '_format_float',
    t => '_format_timestamp',
    s => '_format_string',
    n => '_format_numbered',
    N => '_format_numbered',
  };
}

sub default_input_processor { 'require_named_input' }
sub default_format_hunker   { '__hunk_errf' }
sub default_string_replacer { '__replace_errf' }
sub default_hunk_formatter  { '__format_errf' }

my $regex = qr/
 (%                   # leading '%'
  (?:{                # {
    (.*?)             #   mandatory argument name
    (?: ; (.*?) )?    #   optional extras after semicolon
  })                  # }
  ([a-z])             # actual conversion character
 )
/xi;

sub __hunk_errf {
  my ($self, $string) = @_;

  my @to_fmt;
  my $pos = 0;

  while ($string =~ m{\G(.*?)$regex}gs) {
    push @to_fmt, $1, {
      literal     => $2,
      argument    => $3,
      extra       => $4,
      conversion  => $5,
    };

    $pos = pos $string;
  }

  push @to_fmt, substr $string, $pos if $pos < length $string;

  return \@to_fmt;
}

sub __replace_errf {
  my ($self, $hunks, $input) = @_;

  my $heap = {};
  my $code = $self->codes;

  for my $i (grep { ref $hunks->[$_] } 0 .. $#$hunks) {
    my $hunk = $hunks->[ $i ];
    my $conv = $code->{ $hunk->{conversion} };

    Carp::croak("Unknown conversion in stringf: $hunk->{conversion}")
      unless defined $conv;

    $hunk->{replacement} = $input->{ $hunk->{argument} };
    $hunk->{args}        = [ $hunk->{extra} ? split /;/, $hunk->{extra} : () ];
  }
}

sub __format_errf {
  my ($self, $hunk) = @_;

  my $conv = $self->codes->{ $hunk->{conversion} };

  Carp::croak("Unknown conversion in stringf: $hunk->{conversion}")
    unless defined $conv;

  return $self->$conv($hunk->{replacement}, $hunk->{args}, $hunk);
}

sub _proc_args {
  my ($self, $input, $parse_compact) = @_;

  return $input if ref $input eq 'HASH';

  $parse_compact ||= sub {
    Carp::croak("no compact format allowed, but compact format found");
  };

  my @args = @$input;

  my $first = (defined $args[0] and length $args[0] and $args[0] !~ /=/)
            ? shift @args
            : undef;

  my %param = (
    ($first ? %{ $parse_compact->($first) } : ()),
    (map {; split /=/, $_, 2 } @args),
  );

  return \%param;
}

# Likely integer formatting options are:
#   prefix (+ or SPACE for positive numbers)
#
# Other options like (minwidth, precision, fillchar) are not out of the
# question, but if this system is to be used for formatting simple
# user-oriented error messages, they seem really unlikely to be used.  Put off
# supplying them! -- rjbs, 2010-07-30
#
# I'm not even sure that a SPACE prefix is useful, since we're not likely to be
# aligning many of these errors. -- rjbs, 2010-07-30
sub _format_int {
  my ($self, $value, $rest) = @_;

  my $arg = $self->_proc_args($rest, sub {
    my $prefix = index($_[0], '+') >= 0 ? '+'
               : index($_[0], ' ') >= 0 ? ' '
               :                          '';

    return { prefix => $prefix };
  });

  my $int_value = int $value;
  $value = sprintf '%.0f', $value unless $int_value == $value;

  return $value if $value < 0;

  $arg->{prefix} = '' unless defined $arg->{prefix};

  return "$arg->{prefix}$value";
}


# Likely float formatting options are:
#   prefix (+ or SPACE for positive numbers)
#   precision
#
# My remarks above for "int" go for floats, too. -- rjbs, 2010-07-30
sub _format_float {
  my ($self, $value, $rest) = @_;

  my $arg = $self->_proc_args($rest, sub {
    my ($prefix_str, $prec) = $_[0] =~ /\A([ +]?)(?:\.(\d+))?\z/;
    return { prefix => $prefix_str, precision => $prec };
  });

  undef $arg->{precision}
    unless defined $arg->{precision} and length $arg->{precision};

  $arg->{prefix} = '' unless defined $arg->{prefix};

  $value = defined $arg->{precision}
         ? sprintf("%0.$arg->{precision}f", $value)
         : $value;

  return $value < 0 ? $value : "$arg->{prefix}$value";
}

sub _format_timestamp {
  my ($self, $value, $rest) = @_;

  my $arg = $self->_proc_args($rest, sub {
    return { type => $_[0] };
  });

  my $type = $arg->{type} || 'datetime';
  my $zone = $arg->{tz}   || 'local';

  my $format = $type eq 'datetime' ? '%Y-%m-%d %T'
             : $type eq 'date'     ? '%Y-%m-%d'
             : $type eq 'time'     ? '%T'
             : Carp::croak("unknown format type for %t: $type");

  # Supplying a time zone is *strictly informational*. -- rjbs, 2010-10-15
  Carp::croak("illegal time zone for %t: $zone")
    unless $zone eq 'local' or $zone eq 'UTC';

  return Date::Format::time2str($format, $value, ($zone eq 'UTC' ? 'UTC' : ()));
}

sub _format_string {
  my ($self, $value, $rest) = @_;
  return $value;
}

sub _format_numbered {
  my ($self, $value, $rest, $hunk) = @_;

  my $arg = $self->_proc_args($rest, sub {
    my ($word) = @_;

    my ($singular, $divider, $extra) = $word =~ m{\A(.+?)(?: ([/+]) (.+) )?\z}x;

    $divider = '' unless defined $divider; # just to avoid warnings

    my $plural = $divider   eq '/'                 ? $extra
               : $divider   eq '+'                 ? "$singular$extra"
               : $singular  =~ /(?:[xzs]|sh|ch)\z/ ? "${singular}es"
               : $singular  =~ s/y\z/ies/          ? $singular
               :                                     "${singular}s";

    return { singular => $singular, plural => $plural };
  });

  my $formed = abs($value) == 1 ? $arg->{singular} : $arg->{plural};

  return $formed if $hunk->{conversion} eq 'N';

  return sprintf '%s %s',
    $self->_format_float($value, {
      prefix    => $arg->{prefix},
      precision => $arg->{precision},
    }),
    $formed;
}

1;
