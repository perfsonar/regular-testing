package perfSONAR_PS::RegularTesting::Config;

use strict;
use warnings;

our $VERSION = 3.4;

use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);
use Time::HiRes;
use Module::Load;

use perfSONAR_PS::RegularTesting::Test;

my $logger = get_logger(__PACKAGE__);

use Moose;

has 'tests'             => (is => 'rw', isa => 'ArrayRef[perfSONAR_PS::RegularTesting::Test]');
has 'scheduler_modules' => (is => 'rw', isa => 'HashRef[Str]', default => sub { {} });
has 'test_modules'      => (is => 'rw', isa => 'HashRef[Str]', default => sub { {} });

my @test_modules = (
    'perfSONAR_PS::RegularTesting::Tests::Bwctl',
);

my @scheduler_modules = (
    'perfSONAR_PS::RegularTesting::Schedulers::RegularInterval',
);

sub init {
    my ($self, @args) = @_;
    my $parameters = validate( @args, { config => 1 });
    my $config = $parameters->{config};

    foreach my $module (@test_modules) {
        load $module;

        $self->test_modules->{$module->type()} = $module;
    }

    foreach my $module (@scheduler_modules) {
        load $module;

        $self->scheduler_modules->{$module->type()} = $module;
    }

    my ($status, $res) = $self->load_tests({ config => $config });
    unless ($status == 0) {
        return ($status, $res);
    }
}

sub load_tests {
    my ($self, @args) = @_;
    my $parameters = validate( @args, { config => 1 });
    my $config = $parameters->{config};

    unless ($config->{test}) {
        my $msg = "No tests defined";
        $logger->error($msg);
        return (-1, $msg);
    }

    unless (ref($config->{test}) eq "ARRAY") {
        $config->{test} = [ $config->{test} ];

    }

    foreach my $test (@{ $config->{test} }) {
        eval {
            die("Test is missing parameters") unless $test->{parameters};
            die("Test parameters is missing type") unless $test->{parameters}->{type};
            die("Unknown test type: ".$test->{parameters}->{type}) unless $self->test_modules->{$test->{parameters}->{type}};
            die("Test is missing schedule") unless $test->{schedule};
            die("Test schedule is missing type") unless $test->{schedule}->{type};
            die("Unknown schedule type: ".$test->{schedule}->{type}) unless $self->scheduler_modules->{$test->{schedule}->{type}};
            die("Test is missing targets") unless $test->{target};

            $test->{target} = [ $test->{target} ] unless ref($test->{target}) eq "ARRAY";

            my @tests = ();

            my @directions = ();
            if ($self->test_modules->{$test->{parameters}->{type}}->allows_bidirectional()) {
                $logger->debug("Test supports bidirectional");
                if ($test->{parameters}->{send_only}) {
                    $logger->debug("Test is send only");
                    @directions = ( "destination" );
                }
                elsif ($test->{parameters}->{receive_only}) {
                    $logger->debug("Test is receive only");
                    @directions = ( "source" );
                }
                else {
                    $logger->debug("Test is bidirectional");
                    @directions = ( "source", "destination" );
                }
            }
            else {
                $logger->debug("Test doesn't support bidirectional, target receives");
                @directions = ( "destination" );
            }

            foreach my $target (@{ $test->{target} }) {
                foreach my $direction (@directions) {
                    my $test_obj = perfSONAR_PS::RegularTesting::Test->new();

                    my $description;
                    if ($test->{description}) {
                        $description = $test->{description}." for ".$target;
                    }
                    else {
                        $description = $test->{parameters}->{type} . " test for ".$target;
                    }

                    $test_obj->description($description);

                    # XXX: verify that the target is valid

                    if ($direction eq "source") {
                        $test_obj->source($target);
                    }
                    else {
                        $test_obj->destination($target);
                    }

                    my $schedule = $self->parse_schedule({ schedule => $test->{schedule}, config => $config });
                    $test_obj->schedule($schedule);
    
                    my $parameters = $self->parse_test_parameters({ test_parameters => $test->{parameters}, config => $config });
                    $test_obj->parameters($parameters);
    
                    $logger->debug("Adding test: ".$test_obj->description);

                    push @tests, $test_obj;
                }
            }
    
            $self->tests(\@tests);
        };
        if ($@) {
            my $msg = "Problem reading test: $@";
            $logger->error($msg);
            return (-1, $msg);
        };

    }

    return (0, "");
}

sub parse_test_parameters {
    my ($self, @args) = @_;
    my $parameters = validate( @args, { test_parameters => 1, config => 1 });
    my $test_parameters = $parameters->{test_parameters};
    my $config = $parameters->{config};

    my $module = $self->test_modules->{$test_parameters->{type}};

    my $attributes = get_class_attributes($module);

    my $object = $module->new();

    foreach my $attr (keys %$attributes) {
        my $type = $attributes->{$attr};

        my $value;
        if (exists $test_parameters->{$attr}) {
            $value = $test_parameters->{$attr};
        }
        elsif (exists $config->{$attr}) {
            $value = $config->{$attr};
        }

        my $parsed_value = parse_attribute($value, $type);
        $object->$attr($parsed_value) if defined $parsed_value;
    }

    return $object;
}

sub parse_schedule {
    my ($self, @args) = @_;
    my $parameters = validate( @args, { schedule => 1, config => 1 });
    my $schedule = $parameters->{schedule};
    my $config = $parameters->{config};

    my $module = $self->scheduler_modules->{$schedule->{type}};

    my $attributes = get_class_attributes($module);

    my $object = $module->new();

    foreach my $attr (keys %$attributes) {
        my $type = $attributes->{$attr};

        my $value;
        if (exists $schedule->{$attr}) {
            $value = $schedule->{$attr};
        }
        elsif (exists $config->{$attr}) {
            $value = $config->{$attr};
        }

        my $parsed_value = parse_attribute($value, $type);
        $object->$attr($parsed_value) if defined $parsed_value;
    }

    return $object;
}

sub parse_attribute {
    my ($value, $type) = @_;

    my $parsed_value;

    if ($type =~ /ArrayRef\[(.*)\]/) {
        my $array_type = $1;

        my @array = ();
        foreach my $element (@{ $value }) {
            push @array, parse_attribute($element, $array_type);
        }

        $parsed_value = \@array;
    }
    else {
        $parsed_value = $value;
    }

    return $parsed_value;
}

sub get_class_attributes {
    my $class = shift;

    my @ancestors = reverse $class->meta->linearized_isa;

    my %attrs = ();
    foreach my $class (@ancestors) {
        for my $attribute ( map { $class->meta->get_attribute($_) } sort $class->meta->get_attribute_list ) {
            $attrs{$attribute->name} = $attribute->type_constraint unless $attribute->name =~ /^_/;
        }
    }

    return \%attrs;
}

1;
