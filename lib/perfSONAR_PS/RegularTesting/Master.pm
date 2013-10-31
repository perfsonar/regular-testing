package perfSONAR_PS::RegularTesting::Master;

use strict;
use warnings;

our $VERSION = 3.4;

use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);
use Time::HiRes;
use File::Spec;
use File::Path;
use POSIX;
use JSON;

use IPC::DirQueue;

use perfSONAR_PS::RegularTesting::Config;
use perfSONAR_PS::RegularTesting::Master::SelfScheduledTestChild;
use perfSONAR_PS::RegularTesting::Master::MeasurementArchiveChild;

use perfSONAR_PS::RegularTesting::EventQueue::Queue;
use perfSONAR_PS::RegularTesting::EventQueue::Event;

use Moose;

has 'config'        => (is => 'rw', isa => 'perfSONAR_PS::RegularTesting::Config');
has 'exiting'       => (is => 'rw', isa => 'Bool');
has 'children'      => (is => 'rw', isa => 'HashRef', default => sub { {} } );

has 'failed_queues' => (is => 'rw', isa => 'HashRef', default => sub { {} } );
has 'active_queues' => (is => 'rw', isa => 'HashRef', default => sub { {} } );

my $logger = get_logger(__PACKAGE__);

sub init {
    my ($self, @args) = @_;
    my $parameters = validate( @args, { 
                                         config => 1,
                                      });
    my $config = $parameters->{config};

    my $parsed_config = perfSONAR_PS::RegularTesting::Config->new();
    my ($status, $res) = $parsed_config->init({ config => $config });
    if ($status != 0) {
        die("Problem with config file: ".$res);
    }

    $self->config($parsed_config);

    $self->exiting(0);

    # Initialize the queue directories for these measurement_archives
    foreach my $measurement_archive (values %{ $self->config->measurement_archives }) {
        my $queue_directory = $measurement_archive->queue_directory;

        unless ($queue_directory) {
            $queue_directory = File::Spec->catdir($self->config->test_result_directory, $measurement_archive->nonce);
        }

        my $active_directory = File::Spec->catdir($queue_directory, "active");
        my $failed_directory = File::Spec->catdir($queue_directory, "failed");

        foreach my $directory ($active_directory, $failed_directory) {
            $logger->debug("Creating directory: $directory");
            my @directory_errors = ();
            mkpath($directory, { error => \@directory_errors, mode => 0770, verbose => 0 });
            if (scalar(@directory_errors) > 0) {
                die("Problem creating ".$directory.": ".join(",", @directory_errors));
            }
        }

        my $active_queue = IPC::DirQueue->new({ dir => $active_directory });
        my $failed_queue = IPC::DirQueue->new({ dir => $failed_directory });

        $self->active_queues->{$measurement_archive->id} = $active_queue;
        $self->failed_queues->{$measurement_archive->id} = $failed_queue;
    }

    # Initialize the tests before spawning processes
    foreach my $test (values %{ $self->config->tests }) {
        $test->init_test(config => $self->config);
    }

    $SIG{CHLD} = sub {
        $self->handle_child_exit();
    };

    $SIG{TERM} = $SIG{INT} = sub {
        $self->handle_exit();
    };

    return;
}

sub run {
    my ($self) = @_;
    foreach my $measurement_archive (values %{ $self->config->measurement_archives }) {
        $logger->debug("Spawning measurement archive handler: ".$measurement_archive->description);

        my $child = perfSONAR_PS::RegularTesting::Master::MeasurementArchiveChild->new();
        $child->measurement_archive($measurement_archive);
        $child->config($self->config);
        $child->active_queue($self->active_queues->{$measurement_archive->id});
        $child->failed_queue($self->failed_queues->{$measurement_archive->id});

        my $pid = $child->run();
        $self->children->{$pid} = $child;
    }

    foreach my $test (values %{ $self->config->tests }) {
        $logger->debug("Spawning test: ".$test->description);

        my $child = perfSONAR_PS::RegularTesting::Master::SelfScheduledTestChild->new();

        $child->test($test);
        $child->config($self->config);
        $child->ma_queues($self->active_queues);

        my $pid = $child->run();
        $self->children->{$pid} = $child;
    }

    # Sleep waiting to handle various signals
    while (1) {
       sleep(-1);
    }

    return;
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