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

has 'tests'                        => (is => 'rw', isa => 'HashRef[perfSONAR_PS::RegularTesting::Test]', default => sub { {} });
has 'measurement_archives'         => (is => 'rw', isa => 'HashRef[perfSONAR_PS::RegularTesting::MeasurementArchive::Base]', default => sub { {} });
has 'scheduler_modules'            => (is => 'rw', isa => 'HashRef[Str]', default => sub { {} });
has 'test_modules'                 => (is => 'rw', isa => 'HashRef[Str]', default => sub { {} });
has 'measurement_archive_modules'  => (is => 'rw', isa => 'HashRef[Str]', default => sub { {} });
has 'test_result_directory'        => (is => 'rw', isa => 'Str', default => "/var/lib/perfsonar/regular_tests");

my @test_modules = (
    'perfSONAR_PS::RegularTesting::Tests::Bwctl',
    'perfSONAR_PS::RegularTesting::Tests::Bwping',
    'perfSONAR_PS::RegularTesting::Tests::BwpingOwamp',
    'perfSONAR_PS::RegularTesting::Tests::Bwtraceroute',
    'perfSONAR_PS::RegularTesting::Tests::Powstream',
);

my @measurement_archive_modules = (
    'perfSONAR_PS::RegularTesting::MeasurementArchives::Null',
    'perfSONAR_PS::RegularTesting::MeasurementArchives::perfSONARBUOYBwctl',
    'perfSONAR_PS::RegularTesting::MeasurementArchives::PingER',
    'perfSONAR_PS::RegularTesting::MeasurementArchives::TracerouteMA',
    'perfSONAR_PS::RegularTesting::MeasurementArchives::perfSONARBUOYOwamp',
);

my @scheduler_modules = (
    'perfSONAR_PS::RegularTesting::Schedulers::RegularInterval',
    'perfSONAR_PS::RegularTesting::Schedulers::Streaming',
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

    foreach my $module (@measurement_archive_modules) {
        load $module;

        $self->measurement_archive_modules->{$module->type()} = $module;
    }

    $self->load_measurement_archives({ config => $config });

    my ($status, $res) = $self->load_tests({ config => $config });
    unless ($status == 0) {
        return ($status, $res);
    }

    return (0, "");
}

sub load_measurement_archives {
    my ($self, @args) = @_;
    my $parameters = validate( @args, { config => 1 });
    my $config = $parameters->{config};

    my @measurement_archives = ();

    $config->{measurement_archive} = [] unless ($config->{measurement_archive});
    $config->{measurement_archive} = [ $config->{measurement_archive} ] unless (ref($config->{measurement_archive}) eq "ARRAY");

    foreach my $measurement_archive (@{ $config->{measurement_archive} }) {
        my $ma = $self->parse_measurement_archive({ measurement_archive => $measurement_archive });
        $self->measurement_archives->{$ma->id} = $ma;
        push @measurement_archives, $ma;
    }

    return \@measurement_archives;
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

    if ($config->{test_result_directory}) {
        $self->test_result_directory($config->{test_result_directory});
    }

    my %tests = ();

    foreach my $test (@{ $config->{test} }) {
        eval {
            die("Test is missing parameters") unless $test->{parameters};
            die("Test parameters is missing type") unless $test->{parameters}->{type};
            die("Unknown test type: ".$test->{parameters}->{type}) unless $self->test_modules->{$test->{parameters}->{type}};
            die("Test is missing schedule") unless $test->{schedule};
            die("Test schedule is missing type") unless $test->{schedule}->{type};
            die("Unknown schedule type: ".$test->{schedule}->{type}) unless $self->scheduler_modules->{$test->{schedule}->{type}};
            die("Test is missing targets") unless $test->{target};
            die("Test has multiple local addresses") if ($test->{local_address} and ref($test->{local_address}) eq "ARRAY");

            $test->{target} = [ $test->{target} ] unless ref($test->{target}) eq "ARRAY";

            my @directions;
            if ($self->test_modules->{$test->{parameters}->{type}}->allows_bidirectional()) {
                $logger->debug("Test supports bidirectional");
                if ($test->{parameters}->{send_only}) {
                    $logger->debug("Test is send only");
                    @directions = ( "target_is_destination" );
                }
                elsif ($test->{parameters}->{receive_only}) {
                    $logger->debug("Test is receive only");
                    @directions = ( "target_is_source" );
                }
                else {
                    $logger->debug("Test is bidirectional");
                    @directions = ( "target_is_source", "target_is_destination" );
                }
            }
            else {
                $logger->debug("Test doesn't support bidirectional, target receives");
                @directions = ( "target_is_destination" );
            }

            my $measurement_archives = $self->load_measurement_archives({ config => $test });
            if (scalar(@$measurement_archives) == 0) {
                my @global_mas = values %{ $self->measurement_archives() };
                $measurement_archives = \@global_mas;
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

                    if ($direction eq "target_is_source") {
                        $test_obj->source($target);
                        $test_obj->destination($test->{local_address}) if $test->{local_address};
                        $test_obj->destination_local(1);
                    }
                    else {
                        $test_obj->destination($target);
                        $test_obj->source($test->{local_address}) if $test->{local_address};
                        $test_obj->source_local(1);
                    }

                    my $schedule = $self->parse_schedule({ schedule => $test->{schedule}, config => $config });
                    $test_obj->schedule($schedule);
    
                    my $parameters = $self->parse_test_parameters({ test_parameters => $test->{parameters}, config => $config });
                    $test_obj->parameters($parameters);
    
                    unless ($parameters->valid_target({ target => $target })) {
                        die("Target ".$target." is not valid for tests of type ".$parameters->type);
                    }

                    unless ($parameters->valid_schedule({ schedule => $schedule })) {
                        die("Schedule ".$schedule->type." is not valid for tests of type ".$parameters->type);
                    }

                    $test_obj->measurement_archives($measurement_archives);

                    $logger->debug("Adding test: ".$test_obj->description);

                    $tests{$test_obj->id} = $test_obj;
                }
            }
        };
        if ($@) {
            my $msg = "Problem reading test: $@";
            $logger->error($msg);
            return (-1, $msg);
        };
    }

    $self->tests(\%tests);

    return (0, "");
}

sub parse_measurement_archive {
    my ($self, @args) = @_;
    my $parameters = validate( @args, { measurement_archive => 1 });
    my $measurement_archive = $parameters->{measurement_archive};

    my $module = $self->measurement_archive_modules->{$measurement_archive->{type}};

    my $attributes = get_class_attributes($module);

    my $object = $module->new();

    foreach my $attr (keys %$attributes) {
        my $type = $attributes->{$attr};

        my $value = $measurement_archive->{$attr} if (exists $measurement_archive->{$attr});

        my $parsed_value = parse_attribute($value, $type);
        $object->$attr($parsed_value) if defined $parsed_value;
    }

    return $object;
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
