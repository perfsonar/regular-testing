package perfSONAR_PS::RegularTesting::Results::Base;

use strict;
use warnings;

our $VERSION = 3.4;

use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);

use Moose;

my $logger = get_logger(__PACKAGE__);

sub unparse {
    my ($self) = @_;

    my $meta = $self->meta;

    my %description = ();

    for my $attribute ( sort $meta->compute_all_applicable_attributes ) {
        my $variable = $attribute->name;
        my $type     = $attribute->type_constraint;
        my $reader   = $attribute->get_read_method;
        my $value    = $self->$reader;

        next unless (defined $value);

        my $unparsed_value = $self->unparse_attribute({ attribute => $variable, type => $type, value => $value });

        $description{$variable} = $unparsed_value;
    }

    return \%description;
}

sub unparse_attribute {
    my ($self, @args) = @_;
    my $parameters = validate( @args, { attribute => 1, type => 1, value => 1 } );
    my $attribute = $parameters->{attribute};
    my $type      = $parameters->{type};
    my $value     = $parameters->{value};

    my $unparsed_value;

    if ($type =~ /ArrayRef\[(.*)\]/) {
        my @array = ();
        foreach my $element (@$value) {
            if (UNIVERSAL::can($element, "unparse")) {
                push @array, $element->unparse;
            }
            else {
                push @array, $element;
            }
        }

        $unparsed_value = \@array;
    }
    elsif (UNIVERSAL::can($value, "unparse")) {
        $unparsed_value = $value->unparse;
    }
    else {
        $unparsed_value = $value;
    }

    return $unparsed_value;
}

1;
