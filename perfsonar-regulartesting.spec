%define install_base /usr/lib/perfsonar/
%define config_base  /etc/perfsonar

# init scripts must be located in the 'scripts' directory
%define init_script_1 perfsonar-regulartesting

%define relnum   0.0.a1 

Name:			perfsonar-regulartesting
Version:		3.5.1
Release:		%{relnum}
Summary:		perfSONAR Regular Testing
License:		Distributable, see LICENSE
Group:			Development/Libraries
URL:			http://search.cpan.org/dist/perfSONAR-RegularTesting/
Source0:		perfsonar-regulartesting-%{version}.%{relnum}.tar.gz
BuildRoot:		%{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:		noarch
Obsoletes:      perl-perfSONAR_PS-RegularTesting

Requires:		perl(Carp)
Requires:		perl(Class::MOP::Class)
Requires:		perl(Config::General)
Requires:		perl(DBI)
Requires:		perl(Data::UUID)
Requires:		perl(Data::Validate::Domain)
Requires:		perl(Data::Validate::IP)
Requires:		perl(DateTime)
Requires:		perl(DateTime::Format::ISO8601)
Requires:		perl(Digest::MD5)
Requires:		perl(English)
Requires:		perl(Exporter)
Requires:		perl(Fcntl)
Requires:		perl(File::Path)
Requires:		perl(File::Spec)
Requires:		perl(File::Temp)
Requires:		perl(FindBin)
Requires:		perl(Getopt::Long)
Requires:		perl(HTTP::Response)
Requires:		perl(IO::Select)
Requires:		perl(IO::Socket::SSL)
Requires:		perl(IO::Socket::INET6)
Requires:		perl(IPC::DirQueue)
Requires:		perl(IPC::Open3)
Requires:		perl(IPC::Run)
Requires:		perl(JSON)
Requires:		perl(Log::Log4perl)
Requires:		perl(Math::Int64)
Requires:		perl(Module::Load)
Requires:		perl(Moose)
Requires:		perl(Net::DNS)
Requires:		perl(Net::IP)
Requires:		perl(Net::Traceroute)
Requires:		perl(NetAddr::IP)
Requires:		perl(POSIX)
Requires:		perl(Params::Validate)
Requires:		perl(Regexp::Common)
Requires:		perl(Statistics::Descriptive)
Requires:		perl(Symbol)
Requires:		perl(Time::HiRes)
Requires:		perl(URI::Split)

%description
The perfSONAR-PS Regular Testing package allows the configuration of regular
tests whose results are stored in a perfSONAR Measurement Archive.

%pre
/usr/sbin/groupadd perfsonar 2> /dev/null || :
/usr/sbin/useradd -g perfsonar -r -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :

%prep
%setup -q -n perfsonar-regulartesting-%{version}.%{relnum}

%build

%install
rm -rf %{buildroot}

make ROOTPATH=%{buildroot}/%{install_base} CONFIGPATH=%{buildroot}/%{config_base} install

mkdir -p %{buildroot}/etc/init.d

install -D -m 0755 scripts/%{init_script_1} %{buildroot}/etc/init.d/%{init_script_1}
rm -rf %{buildroot}/%{install_base}/scripts/

%clean
rm -rf %{buildroot}

%post
mkdir -p /var/lib/perfsonar/regular_testing
chown perfsonar:perfsonar /var/lib/perfsonar/regular_testing

if [ "$1" = "2" ]; then

    #Update config file. For 3.5.1 will symlink to old location. In 3.6 we will move it.
    if [ -L "%{config_base}/regulartesting.conf" ]; then
        echo "WARN: /opt/perfsonar_ps/regular_testing/etc/regular_testing.conf will be moved to %{config_base}/regulartesting.conf in 3.6. Update configuration management software as soon as possible. "
    elif [ -e "/opt/perfsonar_ps/regular_testing/etc/regular_testing.conf" ]; then
        mv %{config_base}/regulartesting.conf %{config_base}/regulartesting.conf.default
        ln -s /opt/perfsonar_ps/regular_testing/etc/regular_testing.conf %{config_base}/regulartesting.conf
    fi
    
     #Update logging config file. For 3.5.1 will symlink to old location. In 3.6 we will move it.
    if [ -L "%{config_base}/regulartesting-logger.conf" ]; then
        echo "WARN: /opt/perfsonar_ps/regular_testing/etc/regular_testing-logger.conf will be moved to %{config_base}/regulartesting-logger.conf in 3.6. Update configuration management software as soon as possible. "
    elif [ -e "/opt/perfsonar_ps/regular_testing/etc/regular_testing-logger.conf" ]; then
        mv %{config_base}/regulartesting-logger.conf %{config_base}/regulartesting-logger.conf.default
        ln -s /opt/perfsonar_ps/regular_testing/etc/regular_testing-logger.conf %{config_base}/regulartesting-logger.conf
    fi
fi

/sbin/chkconfig --add regular_testing


%files
%defattr(0644,perfsonar,perfsonar,0755)
%config(noreplace) %{config_base}/*
%attr(0755,perfsonar,perfsonar) %{install_base}/bin/*
%{install_base}/lib/*
%attr(0755,perfsonar,perfsonar) /etc/init.d/*

%changelog
* Thu Jun 19 2014 andy@es.net 3.4-7
- Added support for new MA

* Tue Jan 14 2013 aaron@internet2.edu 3.4-1
- Initial RPM
