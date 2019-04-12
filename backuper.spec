Name:           backuper
Version:        19.04.12
Release:        14.47
Summary:        Backup manager
License:        -

Source0:        backuper.sh
Source1:        backuper.cfg
Source2:        default.cfg
Source3:        netoff.service

BuildArch:      noarch

BuildRoot:      %(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)

Requires: rsync cifs-utils ntfs-3g ntfsprogs samba-client

%description
Backup manager from samba servers

%install
install -D -pm 755 %{SOURCE0} %{buildroot}%{_bindir}/backuper
install -D -pm 644 %{SOURCE1} %{buildroot}%{_sysconfdir}/backuper/backuper.cfg
install -D -pm 644 %{SOURCE2} %{buildroot}%{_sysconfdir}/backuper/config/default.cfg
install -D -pm 644 %{SOURCE3} %{buildroot}%{_unitdir}/netoff.service

%files
%{_bindir}/backuper
%{_unitdir}/netoff.service
%{_sysconfdir}/backuper/backuper.cfg
%{_sysconfdir}/backuper/config/default.cfg

%clean
rm -rf $RPM_BUILD_ROOT

