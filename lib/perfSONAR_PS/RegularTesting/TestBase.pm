package perfSONAR_PS::RegularTesting::TestBase;

use strict;
use warnings;

our $VERSION = 3.4;

use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);

use Moose;
use Class::MOP::Class;

my $logger = get_logger(__PACKAGE__);

has 'test_config' => (is => 'rw', isa => 'HashRef');
has 'description' => (is => 'rw', isa => 'Str');

sub init {
    my ($self, @args) = @_;
    my $parameters = validate( @args, { test_config => 1, strict => 0 });
    my $test_config = $parameters->{test_config};
    my $strict = $parameters->{strict};

    for my $attribute ( $self->get_all_attributes ) {
        my $variable = $attribute->name;
        my $type     = $attribute->type_constraint;
        my $writer   = $attribute->get_write_method;

        $logger->debug("Parsing: $variable");

        next unless (defined $test_config->{$variable});

        $logger->debug("$variable is defined");

        my $parsed_value;

        $type = $type.""; # convert to string

        if ($type =~ /ArrayRef\[(.*)\]/) {
            my $array_type = $1;

            my @array = ();
            foreach my $element (@{ $test_config->{$variable} }) {
                my $parsed;
                if ($array_type =~ /perfSONAR_PS::RegularTesting::/) { # XXX: handle this better
                    $parsed = $array_type->parse($element, $strict);
                }
                else {
                    $parsed = $element;
                }

                push @array, $parsed;
            }

            $parsed_value = \@array;
        }
        elsif ($type =~ /perfSONAR_PS::RegularTesting::/) { # XXX: handle this better
            $parsed_value = $type->parse($test_config->{$variable}, $strict);
        }
        else {
            $parsed_value = $test_config->{$variable};
        }

        $self->$writer($parsed_value) if defined $parsed_value;
    }

    if ($strict) {
        foreach my $key (keys %$test_config) {
            unless (UNIVERSAL::can($self, $key)) {
                die("Unknown attribute: $key");
            }
        }
    }

    return;
}

sub get_all_attributes {
    my $self = shift;

    my @ancestors = reverse $self->meta->linearized_isa;

    my %attrs = ();
    foreach my $class (@ancestors) {
        for my $attribute ( map { $class->meta->get_attribute($_) } sort $class->meta->get_attribute_list ) {
            $attrs{$attribute->name} = $attribute;
        }
    }

    return values %attrs;
}

sub run_tests {
    my ($self) = @_;

    die("run_tests() method needs to be overridden");
}

sub store_results {
    my ($self, $results) = @_;

    die("store_results() method needs to be overridden");
}

1;
