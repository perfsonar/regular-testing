%define install_base /usr/lib/perfsonar/
%define config_base  /etc/perfsonar

# init scripts must be located in the 'scripts' directory
%define init_script_1 perfsonar-regulartesting

%define relnum   0.1.a1 

Name:			perfsonar-regulartesting
Version:		3.5.1
Release:		%{relnum}
Summary:		perfSONAR Regular Testing
License:		Distributable, see LICENSE
Group:			Development/Libraries
URL:			http://www.perfsonar.net
Source0:		perfsonar-regulartesting-%{version}.%{relnum}.tar.gz
BuildRoot:		%{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:		noarch
Obsoletes:      perl-perfSONAR_PS-RegularTesting
Requires:		libperfsonar-regulartesting-perl
Requires:		libperfsonar-perl

%description
The perfSONAR Regular Testing package allows the configuration of regular
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
mkdir -p /var/lib/perfsonar/regulartesting
chown perfsonar:perfsonar /var/lib/perfsonar/regulartesting

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

/sbin/chkconfig --add perfsonar-regulartesting


%files
%defattr(0644,perfsonar,perfsonar,0755)
%config(noreplace) %{config_base}/*
%attr(0755,perfsonar,perfsonar) %{install_base}/bin/*
%attr(0755,perfsonar,perfsonar) /etc/init.d/*

%changelog
* Thu Jun 19 2014 andy@es.net 3.4-7
- Added support for new MA

* Tue Jan 14 2013 aaron@internet2.edu 3.4-1
- Initial RPM
