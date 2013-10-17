package perfSONAR_PS::RegularTesting::Master;

use strict;
use warnings;

our $VERSION = 3.4;

use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);
use Time::HiRes;
use File::Spec;
#use File::Path qw(make_path);
use File::Path;
use POSIX;
use JSON;

use perfSONAR_PS::RegularTesting::Config;
use perfSONAR_PS::RegularTesting::Master::TesterChild;
use perfSONAR_PS::RegularTesting::Master::MeasurementArchiveChild;

use perfSONAR_PS::RegularTesting::EventQueue::Queue;
use perfSONAR_PS::RegularTesting::EventQueue::Event;

use Moose;

has 'config'       => (is => 'rw', isa => 'perfSONAR_PS::RegularTesting::Config');
has 'exiting'      => (is => 'rw', isa => 'Bool');
has 'children'     => (is => 'rw', isa => 'HashRef', default => sub { {} } );
has 'event_queue'  => (is => 'rw', isa => 'perfSONAR_PS::RegularTesting::EventQueue::Queue');

my $logger = get_logger(__PACKAGE__);

sub init {
    my ($self, @args) = @_;
    my $parameters = validate( @args, { 
                                         config => 1,
                                      });
    my $config = $parameters->{config};

    my $parsed_config = perfSONAR_PS::RegularTesting::Config->new();
    $parsed_config->init({ config => $config });

    $self->config($parsed_config);

    $self->event_queue(perfSONAR_PS::RegularTesting::EventQueue::Queue->new());

    $self->exiting(0);

    # Initialize the queue directories for these measurement_archives
    foreach my $measurement_archive (values %{ $self->config->measurement_archives }) {
        unless ($measurement_archive->queue_directory) {
            my $directory = File::Spec->catdir($self->config->test_result_directory, $measurement_archive->nonce);
            $measurement_archive->queue_directory($directory);
        }

        my @directory_errors = ();
        mkpath($measurement_archive->queue_directory, { error => \@directory_errors, mode => 0770 });
        if (scalar(@directory_errors) > 0) {
            die("Problem creating ".$measurement_archive->queue_directory.": ".join(",", @directory_errors));
        }
    }

    return;
}

sub run {
    my ($self) = @_;

    $SIG{CHLD} = sub {
        $self->handle_child_exit();
    };

    $SIG{TERM} = $SIG{INT} = sub {
        $self->handle_exit();
    };

    foreach my $measurement_archive (values %{ $self->config->measurement_archives }) {
        $logger->debug("Spawning measurement archive handler: ".$measurement_archive->description);

        my $child = perfSONAR_PS::RegularTesting::Master::MeasurementArchiveChild->new(measurement_archive => $measurement_archive, config => $self->config);

        my $pid = $child->run();
        $self->children->{$pid} = $child;
    }

    foreach my $test (values %{ $self->config->tests }) {
        $logger->debug("Spawning test: ".$test->description);

        my $child = perfSONAR_PS::RegularTesting::Master::TesterChild->new(test => $test, config => $self->config);

        my $event = perfSONAR_PS::RegularTesting::EventQueue::Event->new(time => $test->calculate_next_run_time(), private => { child => $child, action => "start_test" });
        $self->event_queue->insert($event);

        my $pid = $child->run();
        $self->children->{$pid} = $child;
    }

    $self->main_loop();

    return;
}

sub main_loop {
    my ($self) = @_;

    while (1) {
       my $event;
       do {
           $event = $self->event_queue->pop();
           sleep(-1) unless $event; # Wait for an event to pop up. XXX: no way for this to happen.
       } while (not $event);

       my $sleep_time = $event->time - time;
       while ($sleep_time > 0) {
           sleep($sleep_time);

           $sleep_time = $event->time - time;
       }

       if ($event->{private}->{action} eq "start_test") {
           $event->{private}->{child}->start_test();
       }

    }
}

sub handle_child_exit {
    my ($self) = @_;

    while( ( my $pid = waitpid( -1, &WNOHANG ) ) > 0 ) {
        my $child = $self->children->{$pid};
        if (not $child) {
            $logger->debug("Received SIGCHLD for unknown PID: ".$pid);
            next;
        }

        delete($self->children->{$pid});

        unless ($self->exiting) {
            $logger->debug("Child exited. Restarting...");

            my $pid = $child->run();
            $self->children->{$pid} = $child;
        }
    }

    return;
}

sub handle_exit {
    my ($self) = @_;

    $self->exiting(1);

    if (scalar(keys %{ $self->children }) > 0) {
        foreach my $pid (keys %{ $self->children }) {
            my $child = $self->children->{$pid};
            $child->kill_child();
        }

        # Wait a second for processes to exit
        my $waketime = time + 1;
        while ((my $sleep_time = $waketime - time) > 0 and 
               scalar keys %{ $self->children } > 0) {
            sleep($sleep_time);
        }

        foreach my $pid (keys %{ $self->children }) {
            my $child = $self->children->{$pid};
            $logger->debug("Child $pid hasn't exited. Sending SIGKILL");
            $child->kill_child({ force => 1 });
        }
    }

    $logger->debug("Process '".$0."' exiting");

    exit(0);
}

1;
