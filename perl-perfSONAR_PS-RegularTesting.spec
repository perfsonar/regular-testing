%define install_base /opt/perfsonar_ps/regular_testing

# init scripts must be located in the 'scripts' directory
%define init_script_1 regular_testing

%define relnum 1
%define disttag pSPS

Name:			perl-perfSONAR_PS-RegularTesting
Version:		3.3.2
Release:		%{relnum}.%{disttag}
Summary:		perfSONAR_PS Regular Testing
License:		Distributable, see LICENSE
Group:			Development/Libraries
URL:			http://search.cpan.org/dist/perfSONAR_PS-RegularTesting/
Source0:		perfSONAR_PS-RegularTesting-%{version}.%{relnum}.tar.gz
BuildRoot:		%{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:		noarch

%description
The perfSONAR-PS Regular Testing package allows the configuration of regular
tests whose results are stored in a perfSONAR Measurement Archive.

%pre
/usr/sbin/groupadd perfsonar 2> /dev/null || :
/usr/sbin/useradd -g perfsonar -r -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :

%prep
%setup -q -n perfSONAR_PS-RegularTesting-%{version}.%{relnum}

%build

%install
rm -rf %{buildroot}

make ROOTPATH=%{buildroot}/%{install_base} rpminstall

mkdir -p %{buildroot}/etc/init.d

awk "{gsub(/^PREFIX=.*/,\"PREFIX=%{install_base}\"); print}" scripts/%{init_script_1} > scripts/%{init_script_1}.new
install -D -m 0755 scripts/%{init_script_1}.new %{buildroot}/etc/init.d/%{init_script_1}

%clean
rm -rf %{buildroot}

%post
mkdir -p /var/lib/perfsonar/regular_testing
chown perfsonar:perfsonar /var/lib/perfsonar/regular_testing

/sbin/chkconfig --add regular_testing

%files
%defattr(0644,perfsonar,perfsonar,0755)
#%doc %{install_base}/doc/*
%config %{install_base}/etc/*
%attr(0755,perfsonar,perfsonar) %{install_base}/bin/*
%attr(0755,perfsonar,perfsonar) %{install_base}/scripts/*
%{install_base}/lib/*
%{install_base}/dependencies
%attr(0755,perfsonar,perfsonar) /etc/init.d/*

%changelog
* Wed Dec 04 2013 aaron@internet2.edu 3.3.2-1
- Initial RPM
