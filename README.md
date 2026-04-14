### Welcome! This is an easy to use installer that helps you set up Steam, WiVRn, Proton-GE-RTSP, VRChat, and optionally WayVR on any Debian based system. Be sure to have your graphics driver installed and configured first!  


#### To install Steam, VRChat, WiVRn, Proton-GE-RTSP, and optionally WayVR:

```
curl -fsSL https://raw.githubusercontent.com/MagnetosphereLabs/vrc-linux-setup/main/vrchat-linux-setup.sh | sudo bash -s install
```

#### To Uninstall those:

```
curl -fsSL https://raw.githubusercontent.com/MagnetosphereLabs/vrc-linux-setup/main/vrchat-linux-setup.sh | sudo bash -s uninstall-all
```

#### To update important software managed by this script:

```
curl -fsSL https://raw.githubusercontent.com/MagnetosphereLabs/vrc-linux-setup/main/vrchat-linux-setup.sh | sudo bash -s update
```

#### If EAC becomes a problem this will move VRChat's Proton prefix aside so Steam regenerates it next launch which can fix issues:

```
curl -fsSL https://raw.githubusercontent.com/MagnetosphereLabs/vrc-linux-setup/main/vrchat-linux-setup.sh | sudo bash -s repair-eac
```

#### To detect an existing or partial setup and correct/reinstall only what is needed:

```
curl -fsSL https://raw.githubusercontent.com/MagnetosphereLabs/vrc-linux-setup/main/vrchat-linux-setup.sh | sudo bash -s repair-install
```

#### To check the current status of the installed software:

```
curl -fsSL https://raw.githubusercontent.com/MagnetosphereLabs/vrc-linux-setup/main/vrchat-linux-setup.sh | sudo bash -s status
```

#### To check the current Proton-GE-RTSP release notes:

```
curl -fsSL https://raw.githubusercontent.com/MagnetosphereLabs/vrc-linux-setup/main/vrchat-linux-setup.sh | sudo bash -s rtsp-changelog
```

#### To check the current WayVR release notes:

```
curl -fsSL https://raw.githubusercontent.com/MagnetosphereLabs/vrc-linux-setup/main/vrchat-linux-setup.sh | sudo bash -s wayvr-changelog
```
