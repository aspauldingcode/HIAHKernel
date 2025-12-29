let's re-think all of this.
instead of bypass dyld signature issue
here's what we'll do:
something similar to LiveProcess.
However, LiveProcess has ability to use sidestore.
I believe this is how it works. 

steps:
0 - install sidestore.
1 - sidestore can install LiveProcess.
2. - liveprocess can use sidestore's vpn, + sidestore's other features to bypass dyld signature issues, and/or enable JIT from sidestore

here's what I'd like to do instead:

1. users install HIAH Desktop
2. Users login to HIAH Desktop using HIAH LoginWindow
3. after they sign in using their apple id and password, they're able to use HIAH Desktop's process spawning feature with dyld bypass of LiveProcess, as LiveProcess basically uses Sidestore and Sidestore's loopback VPN to get sidestore working and some JIT working
4. Then, we can use the desktop like normal. however this time, I can install .ipa applications, and run them inside HIAH Desktop using our sidestore integration to bypass dyld signature verivication using LIveProcess's sidestore+sidestorevpn loopback and jitless sidestore integration method. 

We're going to write our very own Sidestore for HIAH Desktop. instead of sideloading HIAH Desktop app with Sidestore, we're going to integrate a custom sidestore inside HIAH Desktop project, which will be called HIAH LoginWindow. since users must be signed in with appleid, it can use the same exact functionality as sidestore while being inside HIAH Desktop, but the user no longer requuires to install sidestore seperately - all a standalone app. This time, users can install and use software like .jar files and java jdk dev which require JIT.. HIAH LoginWindow will be split into a couple parts. HIAH LoginWindow will be basically sidestore's appleid login for signing other ipa files. HIAH LoginWindow will look like a true desktop or mobile login window, Where users have to log in to access their desktop. after signin, we can do what sidestore does, we won't have to sign in every single time. Sidestore does sideload apps with .ipa. instead, we're going to plan on using sidestore integration for its JIT or loopback vpn features - we'll extract the .ipa into a .app and place into HIAH Desktop's Applications folder. Then, HIAH Desktop will execute it by LiveProcess's method of connecting over to Sidestore + VPN loopback with LiveProcess's "Jitless" method.

sidestore has AGPLv3 license. Keep this in mind for HIAH LoginWindow (essentially the Sidestore built for HIAH Desktop integration). 

We will make everything our custom integration. However, we must create dependencies for Sidestore and all of sidestore's dependencies using our Nix Tooling. 

1 - EM Proxy
2 - Minimuxer
3 - Roxas
4 - Sidestore is an Altserver fork. We need to fork Sidestore into HIAH LoginWindow.. and HIAH ProcessRunner for LiveProcess style sidestore integration for dyld signature bypass.
Altserver features... without an AltServer. Sidestore refreshes the 7 day signing, without having to re-install Sidestore. This is exactly what I'd like to create for HIAH Desktop. if Users install HIAH Desktop, we use HIAH LoginWindow's second part, of Sidestore to re-sign HIAH Desktop and keep it available for the user. This is why HIAH LoginWindow is required. 

SideStore is an iOS application that allows you to sideload apps onto your iOS device with just your Apple ID. SideStore resigns apps with your personal development certificate, and then uses a specially designed VPN in order to trick iOS into installing them. SideStore will periodically "refresh" your apps in the background, to keep their normal 7-day development period from expiring.

SideStore's goal is to provide an untethered sideloading experience. It's a community driven fork of AltStore, and has already implemented some of the community's most-requested features.

(Contributions are welcome! 🙂)

Requirements

Xcode 15
iOS 14+
Rustup (brew install rustup)
Why iOS 14? Targeting such a recent version of iOS allows us to accelerate development, especially since not many developers have older devices to test on. This is corrobated by the fact that SwiftUI support is much better, allowing us to transistion to a more modern UI codebase.

Project Overview

SideStore

SideStore is a just regular, sandboxed iOS application. The AltStore app target contains the vast majority of SideStore's functionality, including all the logic for downloading and updating apps through SideStore. SideStore makes heavy use of standard iOS frameworks and technologies most iOS developers are familiar with.

EM Proxy

EM Proxy powers the defining feature of SideStore: untethered app installation. By leveraging a custom-built App Store app with additional entitlements (LocalDevVPN) to create the VPN tunnel for us, it allows SideStore to take advantage of Jitterbug's loopback method without requiring a paid developer account.

Minimuxer

Minimuxer is a lockdown muxer that can run inside iOS’s sandbox. It replicates Apple’s usbmuxd protocol on macOS to “discover” devices to interface with LocalDevVPN on-device.

Roxas

Roxas is Riley Testut's internal framework from AltStore used across many of their iOS projects, developed to simplify a variety of common tasks used in iOS development.

We're hoping to eventually eliminate our dependency on it, as it increases the amount of unnecessary Objective-C in the project.

Contributing/Compilation Instructions

Please see CONTRIBUTING.md

Licensing

This project is licensed under the AGPLv3 license.

we can use pkgCross or whatever. we need to make our entire nix tooling create the source available. we basically need to rewrite Sidestore while depending on it still. we need to rewrite it into our own implementation, HIAH LoginWindow. ALl features of sidestore need to be present. it is absoliutely important we get this right, please look at the source code of sidestore at ./source2. 

And, Sidestore is available at github, use our nix tooling to integrate into the build of HIAH LoginWindow and HIAH Desktop.