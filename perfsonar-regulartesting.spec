%define install_base /usr/lib/perfsonar/
%define config_base  /etc/perfsonar

# init scripts must be located in the 'scripts' directory
%define init_script_1 perfsonar-regulartesting

%define relnum   1 

Name:			perfsonar-regulartesting
Version:		3.5.1.1
Release:		%{relnum}%{?dist}
Summary:		perfSONAR Regular Testing
License:		Distributable, see LICENSE
Group:			Development/Libraries
URL:			http://www.perfsonar.net
Source0:		perfsonar-regulartesting-%{version}.%{relnum}.tar.gz
BuildRoot:		%{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:		noarch
Requires:		libperfsonar-regulartesting-perl
Requires:		libperfsonar-perl
Obsoletes:      perl-perfSONAR_PS-RegularTesting
Provides:       perl-perfSONAR_PS-RegularTesting

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

if [ "$1" = "1" ]; then
     # clean install, check for pre 3.5.1 files
    if [ -e "/opt/perfsonar_ps/regular_testing/etc/regular_testing.conf" ]; then
        mv %{config_base}/regulartesting.conf %{config_base}/regulartesting.conf.default
        mv /opt/perfsonar_ps/regular_testing/etc/regular_testing.conf %{config_base}/regulartesting.conf
        sed -i "s:/var/lib/perfsonar/regular_testing:/var/lib/perfsonar/regulartesting:g" %{config_base}/regulartesting.conf
    fi
    
    if [ -e "/opt/perfsonar_ps/regular_testing/etc/regular_testing-logger.conf" ]; then
        mv %{config_base}/regulartesting-logger.conf %{config_base}/regulartesting-logger.conf.default
        mv /opt/perfsonar_ps/regular_testing/etc/regular_testing-logger.conf %{config_base}/regulartesting-logger.conf
        sed -i "s:regular_testing.log:regulartesting.log:g" %{config_base}/regulartesting-logger.conf
    fi
    
    #pre 3.5.1 only, stop the old service since the old rpms did not restart on install 
    if [ -e /etc/init.d/regular_testing ]; then
        /etc/init.d/regular_testing stop
        /sbin/chkconfig --del regular_testing
        /etc/init.d/%{init_script_1} restart
    fi
fi

/sbin/chkconfig --add perfsonar-regulartesting

%preun
if [ "$1" = "0" ]; then
	# Totally removing the service
	/etc/init.d/%{init_script_1} stop
	/sbin/chkconfig --del %{init_script_1}
fi

%postun
if [ "$1" != "0" ]; then
	# An RPM upgrade
	/etc/init.d/%{init_script_1} restart
fi

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
