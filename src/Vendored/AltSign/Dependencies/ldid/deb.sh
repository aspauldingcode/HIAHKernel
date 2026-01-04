#!/nix/store/p0k9r5h8qs7220xdbdihhfgzwjcly70x-bash-5.3p3/bin/bash
rm -rf _
mkdir -p _/usr/bin
cp -a ios/ldid _/usr/bin/ldid
mkdir -p _/DEBIAN
./control.sh _ >_/DEBIAN/control
mkdir -p debs
ln -sf debs/ldid_$(./version.sh)_iphoneos-arm.deb ldid.deb
dpkg-deb -b _ ldid.deb
readlink ldid.deb
