package perfSONAR_PS::RegularTesting::MeasurementArchives::perfSONARBUOYBwctl;

use strict;
use warnings;

our $VERSION = 3.4;

use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);

use Math::Int64 qw(uint64 uint64_to_number);
use Digest::MD5;

use DBI;

use Moose;

use perfSONAR_PS::RegularTesting::Results::ThroughputTest;

extends 'perfSONAR_PS::RegularTesting::MeasurementArchives::Base';

has 'host' => (is => 'rw', isa => 'Str');
has 'username' => (is => 'rw', isa => 'Str');
has 'password' => (is => 'rw', isa => 'Str');
has 'database' => (is => 'rw', isa => 'Str');

has '_dates_initialized' => (is => 'rw', isa => 'HashRef', default => sub { {} });

my $logger = get_logger(__PACKAGE__);

override 'type' => sub { "perfsonarbuoy/bwctl" };

override 'accepts_results' => sub {
    my ($self, @args) = @_;
    my $parameters = validate( @args, { type => 1, });
    my $type = $parameters->{type};

    $logger->debug("accepts_results: $type");

    return ($type eq "throughput");
};

override 'nonce' => sub {
    my ($self) = @_;

    my $nonce = "";
    $nonce .= ($self->host?$self->host:"localhost");
    $nonce .= "_".$self->database;

    return $nonce;
};

override 'store_results' => sub {
    my ($self, @args) = @_;
    my $parameters = validate( @args, {
                                         results => 1,
                                      });
    my $results = $parameters->{results};

    eval {
        $results = perfSONAR_PS::RegularTesting::Results::ThroughputTest->parse($results);

        my $dbh = DBI->connect("dbi:mysql:".$self->database, $self->username, $self->password, { RaiseError => 0, PrintError => 0 });
        unless ($dbh) {
            die("Problem connecting to database: $@");
        }

        $logger->debug("Connected to DB");

        my $testspec_id    = $self->add_testspec(dbh => $dbh, results => $results);
        unless ($testspec_id) {
            die("Couldn't get test spec");
        }

        $logger->debug("Got test spec: $testspec_id");

        my $source_id      = $self->add_endpoint(dbh => $dbh, date => $results->test_time, endpoint => $results->source);
        unless ($source_id) {
            die("Couldn't get source node");
        }

        $logger->debug("Got source id: $source_id");

        my $destination_id = $self->add_endpoint(dbh => $dbh, date => $results->test_time, endpoint => $results->destination);
        unless ($source_id) {
            die("Couldn't get destination node");
        }

        $logger->debug("Got destination id: $destination_id");

        my ($status, $res) = $self->add_data(dbh => $dbh,
                                             testspec_id => $testspec_id,
                                             source_id   => $source_id,
                                             destination_id => $destination_id,
                                             results => $results
                                            );

        if ($status != 0) {
            die("Couldn't save data: $res");
        }
    };
    if ($@) {
        my $msg = "Problem saving results: $@";
        $logger->error($msg);
        return (-1, $msg);
    }

    return (0, "");
};

sub add_testspec {
    my ($self, @args) = @_;
    my $parameters = validate( @args, {
                                         dbh => 1,
                                         results => 1,
                                      });
    my $dbh     = $parameters->{dbh};
    my $results = $parameters->{results};

    my $is_udp = $results->source->protocol eq "udp"?1:0;

    my %testspec_properties = (
        udp => $is_udp,
        duration => $results->time_duration,
        udp_bandwidth => $results->bandwidth_limit,
        len_buffer => $results->buffer_length,
        window_size => $results->window_size,
        parallel_streams => $results->streams,
        tos => $results->tos_bits,
    );

    my ($status, $res) = $self->query_element(dbh => $dbh,
                                              type => "testspec",
                                              date => $results->test_time,
                                              properties => \%testspec_properties,
                                             );

    my $testspec_id;
    if ($status == 0) {
        foreach my $result (@$res) {
            $testspec_id = $result->{tspec_id};
        }
    }

    unless ($testspec_id) {
        $testspec_properties{tspec_id} = $self->build_id(\%testspec_properties);

        my ($status, $res) = $self->add_element(dbh => $dbh,
                                                type => "testspec",
                                                date => $results->test_time,
                                                properties => \%testspec_properties,
                                               );

        unless ($status == 0) {
            my $msg = "Couldn't add new test spec";
            $logger->error($msg);
            return;
        }

        $testspec_id = $testspec_properties{tspec_id};
    }

    return $testspec_id;
}

sub add_endpoint {
    my ($self, @args) = @_;
    my $parameters = validate( @args, {
                                         dbh => 1,
                                         date => 1,
                                         endpoint => 1,
                                      });
    my $dbh      = $parameters->{dbh};
    my $date     = $parameters->{date};
    my $endpoint = $parameters->{endpoint};

    my %node_properties = (
        first => 0,
        last  => 0,
    );

    if ($endpoint->address) {
        $node_properties{addr} = $endpoint->address;
    }
    elsif ($endpoint->hostname) {
        $node_properties{addr} = $endpoint->hostname;
    }

    my ($status, $res) = $self->query_element(dbh => $dbh,
                                              type => "nodes",
                                              date => $date,
                                              properties => \%node_properties,
                                             );

    use Data::Dumper;
    $logger->debug("Results for ".Dumper(\%node_properties).": ".Dumper($res));

    my $node_id;
    if ($status == 0) {
        foreach my $result (@$res) {
            $node_id = $result->{node_id};
        }
    }

    unless ($node_id) {
        $node_properties{node_id} = $self->build_id(\%node_properties);

        my ($status, $res) = $self->add_element(dbh => $dbh,
                                                type => "nodes",
                                                date => $date,
                                                properties => \%node_properties,
                                               );

        unless ($status == 0) {
            my $msg = "Couldn't add new node: $res";
            $logger->error($msg);
            return;
        }

        $node_id = $node_properties{node_id};
    }

    return $node_id;
}

sub add_data {
    my ($self, @args) = @_;
    my $parameters = validate( @args, {
                                         dbh => 1,
                                         source_id => 1,
                                         destination_id => 1,
                                         testspec_id => 1,
                                         results => 1,
                                      });
    my $dbh            = $parameters->{dbh};
    my $source_id      = $parameters->{source_id};
    my $testspec_id    = $parameters->{testspec_id};
    my $destination_id = $parameters->{destination_id};
    my $results        = $parameters->{results};

    my %data_properties = (
                send_id => $source_id,
                recv_id => $destination_id,
                tspec_id => $testspec_id,
                ti => datetime2owptstampi($results->test_time),
                timestamp => datetime2owptime($results->test_time),
                throughput => $results->throughput,
                jitter => $results->jitter,
                lost => $results->packets_lost,
                sent => $results->packets_sent,
    );

    use Data::Dumper;
    $logger->debug("Data Properties: ".Dumper(\%data_properties));

    my ($status, $res) = $self->add_element(dbh => $dbh,
                                            type => "data",
                                            date => $results->test_time,
                                            properties => \%data_properties,
                                           );

    unless ($status == 0) {
        my $msg = "Problem adding data";
        $logger->error($msg);
        #return (-1, $msg);
    }

    return (0, "");
}

sub build_id {
    my ($self, $properties) = @_;

    my $md5 = Digest::MD5->new();

    foreach my $attr (keys %$properties) {
        $md5->add($attr);
        $md5->add($properties->{$attr}) if defined $properties->{$attr};
    }

    my $hex = $md5->hexdigest;
    $hex = substr($hex, 0, 8);

    return hex($hex);
}

sub get_dbh {
    my ($self) = @_;

    return DBI->connect("dbi:mysql:".$self->database, $self->username, $self->password, { RaiseError => 0, PrintError => 0 });
}

sub tables {
    return {
        "testspec" => {
            columns => [
                { name => 'tspec_id', type => "INT UNSIGNED NOT NULL" },
                { name => 'description', type => "TEXT(1024)" },
                { name => 'duration', type => "INT UNSIGNED NOT NULL DEFAULT 10" },
                { name => 'len_buffer', type => "INT UNSIGNED" },
                { name => 'window_size', type => "INT UNSIGNED" },
                { name => 'tos', type => "TINYINT UNSIGNED" },
                { name => 'parallel_streams', type => "TINYINT UNSIGNED NOT NULL DEFAULT 1" },
                { name => 'udp', type => "BOOL NOT NULL DEFAULT 0" },
                { name => 'udp_bandwidth', type => "BIGINT UNSIGNED" },
            ],
            primary_key => "tspec_id",
        },
        "nodes" => {
            columns => [
                { name => 'node_id', type => "INT UNSIGNED NOT NULL" },
                { name => 'node_name', type => "TEXT(128)" },
                { name => 'longname', type => "TEXT(1024)" },
                { name => 'addr', type => "TEXT(128)" },
                { name => 'first', type => "INT UNSIGNED NOT NULL" },
                { name => 'last', type => "INT UNSIGNED NOT NULL" },
            ],
            PRIMARY_KEY => "node_id",
        },
        "data" => {
            columns => [
                { name => 'send_id', type => "INT UNSIGNED NOT NULL" },
                { name => 'recv_id', type => "INT UNSIGNED NOT NULL" },
                { name => 'tspec_id', type => "INT UNSIGNED NOT NULL" },
                { name => 'ti', type => "INT UNSIGNED NOT NULL" },
                { name => 'timestamp', type => "BIGINT UNSIGNED NOT NULL" },
                { name => 'throughput', type => "FLOAT" },
                { name => 'jitter', type => "FLOAT" },
                { name => 'lost', type => "BIGINT UNSIGNED" },
                { name => 'sent', type => "BIGINT UNSIGNED" },
            ],
            primary_key => "ti,send_id,recv_id",
            indexes => [ "send_id", "recv_id", "tspec_id" ],
        },
        "dates" => {
            columns => [
                { name => 'year', type => "INT" },
                { name => 'month', type => "INT" },
            ],
            primary_key => "year,month",
            static => 1,
        },
    };
}

sub add_element {
    my ($self, @args) = @_;
    my $parameters = validate( @args, {
                                         dbh  => 1,
                                         type => 1,
                                         date => 1,
                                         ignore => 0,
                                         properties => 1,
                                      });
    my $dbh = $parameters->{dbh};
    my $type = $parameters->{type};
    my $date = $parameters->{date};
    my $ignore = $parameters->{ignore};
    my $properties = $parameters->{properties};

    unless ($self->tables->{$type}) {
        my $msg = "Unknown element type: $type";
        $logger->error($msg);
        return (-1, $msg);
    }

    my ($status, $res) = $self->initialize_tables({ dbh => $dbh, date => $date });
    unless ($status == 0) {
        my $msg = "Couldn't add element: $res";
        $logger->error($msg);
        return (-1, $msg);
    }

    my $table_prefix = $self->time_prefix($date);

    my $table = $table_prefix."_".uc($type);

    return $self->_add_element({ dbh => $dbh, table => $table, ignore => $ignore, properties => $properties });
}

sub _add_element {
    my ($self, @args) = @_;
    my $parameters = validate( @args, {
                                         dbh => 1,
                                         table => 1,
                                         ignore => 0,
                                         properties => 1,
                                      });
    my $dbh = $parameters->{dbh};
    my $table = $parameters->{table};
    my $ignore = $parameters->{ignore};
    my $properties = $parameters->{properties};

    my @keys = keys %$properties;
    my @parameters = map { $properties->{$_} } @keys;
    my @parameter_pointers = map { "?" } @keys;

    my $ignore_parameter = $ignore?"IGNORE":"";

    my $insert_query = "INSERT ".$ignore_parameter." INTO ".$table." (".join(",", @keys).") VALUES (".join(",", @parameter_pointers).")";

    my $sth = $dbh->prepare($insert_query);

    unless ($sth->execute(@parameters)) {
        my $msg = "Problem adding element to database: $DBI::errstr";
        $logger->error($msg);
        return (-1, $msg);
    }

    return (0, "");
}

sub query_element {
    my ($self, @args) = @_;
    my $parameters = validate( @args, {
                                         dbh  => 1,
                                         type => 1,
                                         date => 1,
                                         properties => 1,
                                      });
    my $dbh  = $parameters->{dbh};
    my $type = $parameters->{type};
    my $date = $parameters->{date};
    my $properties = $parameters->{properties};

    unless ($self->tables->{$type}) {
        my $msg = "Unknown element type: $type";
        $logger->error($msg);
        return (-1, $msg);
    }

    my ($status, $res) = $self->initialize_tables({ dbh => $dbh, date => $date });
    unless ($status == 0) {
        my $msg = "Couldn't add element: $res";
        $logger->error($msg);
        return (-1, $msg);
    }

    # XXX: verify the parameters before executing

    my $table_prefix = $self->time_prefix($date);

    my $table = $table_prefix."_".uc($type);

    return $self->_query_element({ dbh => $dbh, table => $table, properties => $properties });
}

sub _query_element {
    my ($self, @args) = @_;
    my $parameters = validate( @args, {
                                         dbh => 1,
                                         table => 1,
                                         properties => 1,
                                      });
    my $dbh = $parameters->{dbh};
    my $table = $parameters->{table};
    my $properties = $parameters->{properties};

    my $query = "SELECT * FROM $table";
    my $query_concat = "WHERE";
    my @query_parameters = ();
    foreach my $property (keys %{ $properties }) {
        if (defined $properties->{$property}) {
            $query .= " ".$query_concat." ".$property."=?";
            push @query_parameters, $properties->{$property};
        }
        else {
            $query .= " ".$query_concat." ".$property." IS NULL";
        }
        $query_concat = "AND";
    }

    $logger->debug("Query: $query");
    use Data::Dumper;
    $logger->debug("Query Parameters: ".Dumper(\@query_parameters));

    my $sth = $dbh->prepare($query);
    unless ($sth) {
        my $msg = "Problem preparing query";
        $logger->error($msg);
        return (-1, $msg);
    }

    unless ($sth->execute(@query_parameters)) {
        my $msg = "Problem executing query";
        $logger->error($msg);
        return (-1, $msg);
    }

    my $results = $sth->fetchall_arrayref({});
    unless ($results) {
        my $msg = "Problem with query";
        $logger->error($msg);
        return (-1, $msg);
    }

    use Data::Dumper;
    $logger->debug("Query Results: ".Dumper($results));

    return (0, $results);
}

sub time_prefix {
    my ($self, $date) = @_;

    return sprintf( '%4.4d%2.2d', $date->year(), $date->month() );
}

sub initialize_tables {
    my ($self, @args) = @_;
    my $parameters = validate( @args, { dbh => 1, date => 1 });
    my $dbh     = $parameters->{dbh};
    my $date    = $parameters->{date};

    my $table_prefix = $self->time_prefix($date);

    return (0, "") if $self->_dates_initialized->{$table_prefix};

    foreach my $table_type (keys %{ $self->tables }) {
        my $table_name;
        if ($self->tables->{$table_type}->{static}) {
            $table_name = uc($table_type);
        }
        else {
            $table_name = $table_prefix."_".uc($table_type);
        }

        my $columns = $self->tables->{$table_type}->{columns};

        my $table_description = join(",", map { $_->{name}." ".$_->{type} } @$columns);

        $logger->debug("Table Description: $table_description");

        if ($self->tables->{$table_type}->{primary_key}) {
            $table_description .= ", PRIMARY KEY(".$self->tables->{$table_type}->{primary_key}.")";
        }

        if ($self->tables->{$table_type}->{indexes}) {
            foreach my $index (@{ $self->tables->{$table_type}->{indexes} }) {
                $table_description .= ", INDEX(".$index.")";
            }
        }

        my $sql = "CREATE TABLE IF NOT EXISTS $table_name ($table_description)";
        $logger->debug("SQL: $sql");

        unless ($dbh->do($sql)) {
            my $msg = "Couldn't create $table_name: $DBI::errstr";
            $logger->error($msg);
            return (-1, $msg);
        }
    }

    # Add the dates to the table
    my %date_properties = (
        year => $date->year(),
        month => $date->month(),
    );

    foreach my $column (@{ $self->tables->{dates}->{columns} }) {
        if ($column->{name} eq "day") {
            $date_properties{day} = $date->day();
        }
    }

    my ($status, $res) = $self->_add_element({ dbh => $dbh, table => "DATES", ignore => 1, properties => \%date_properties });
    if ($status != 0) {
        my $msg = "Problem adding dates to DATES table";
        $logger->error($msg);
        return (-1, $msg);
    }

    $self->_dates_initialized->{$table_prefix} = 1;

    return (0, "");
}

use constant JAN_1970 => 0x83aa7e80;    # offset in seconds
my $scale = uint64(2)**32;

sub datetime2owptime {
    my ($datetime) = @_;

    my $bigtime = uint64($datetime->epoch());
    $bigtime = ($bigtime + JAN_1970) * $scale;
    $bigtime =~ s/^\+//;
    return uint64_to_number($bigtime);
}

sub datetime2owptstampi{
    my ($datetime) = @_;

    my $bigtime = uint64(datetime2owptime($datetime));

    return uint64_to_number($bigtime>>32);
}


1;
