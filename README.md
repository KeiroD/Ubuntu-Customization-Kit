# Ubuntu-Customization-Kit
An old copy of the Ubuntu Customization Kit from https://sourceforge.net/projects/uck/

## Prequisite

A very important prequisite is to install `libfribidi-bin` (`apt install libfribidi-bin`). It is a required dependency that is not present in the uck package. If you don't install it, your custom build will fail with an error when it is almost finished, with a "Failed to build gfxboot theme" error. This is is a bug going back to 12.04 or earlier, so sigh and deal with it, for the time being until someone figures this particular bug out.

## How to Install UCK

Well... this was packaged in a `.deb`, but I'd extracted the `.deb` to upload the `UCK` to GitHub and make things easier for those of us who don't quite trust SourceForge, especially with their shenanigans of late. (e.g., `dpkg -x packagename.deb`)

That said, though... you can typically download [the latest](https://github.com/KeiroD/Ubuntu-Customization-Kit/archive/master.zip) copy of this repository for what it's worth and place it in `/usr/lib`.

Once it's installed, you will be able to call **Ubuntu Customization Kit** from Unity and/or the Administration sub-menu panel in the Start Menu.

## Customizing Your Build

Fire up UCK and follow the prompts. These are the steps:

1. Select which language packs to install. To select multiples just click on each one; you don't need to use shift- or ctrl+click.
2. Select the languages you want available when you boot your live Ubuntu
3. Select your default language
4. Choose your desktop environment or environments
5. Select the Ubuntu installation ISO that you downloaded.
6. Give your build a name, like Ubuntu Cinnamon
7. Do you want to customize the CD manually during building (using package utilities, console, etc.)? Well, of COURSE you do, otherwise why are you here?
8. Do you want to delete all Windows files from the CD? Say yes to save space if you don't plan to mess with Windows
9. Do you want to generate a hybrid image (ISO/USB). Yes you do.
 

Now you'll see a message that the building will now start, with the location of your new ISO. This opens a terminal, and you'll have to enter your `sudo` password. Follow along as it updates package repos, removes unnecessary language packs, and then opens the customization dialog. `Run package manager` opens `Synaptic` so you can select whatever additional packages you want. Use `Synaptic` in the usual way, searching and marking packages for installation. The base packages on your installation ISO are already selected, so you only need to select your chosen extras. Close `Synaptic` when you're finished, and you'll be returned to the customization dialog. You can then return to `Synaptic` if you need to, or select `Continue Building` to go to the next step.

Run `console application` opens a root terminal if you prefer using `apt-get`, or any other custom commands you want to use. For example, you could install `tasksel`, the fabulously useful Debian installation tool that installs package groups such as LAMP Server, Virtual Machine Host, Audio recording and editing suite, various desktops, plus a manual package selector.

Install and run `tasksel` this way from the UCK root console:

```
root@test:/# apt-get install tasksel
root@test:/# tasksel
```

You can generate a list of package groups and their installation status with `tasksel --list-tasks`. `tasksel --task-desc [package group name]` displays the description, and `tasksel --task-packages [package group name]` lists all the packages in the group. Consult `man tasksel` for further options.

When you're finished running commands in the root console `type exit` to return to the customization dialog. You can run `Synaptic` or the `console` again, or select `Continue Building` to go to the next step, which is building your new ISO. This takes just a few minutes, and when it's finished you'll see a `Build Success` dialog that tells you where to find your new Ubuntu image, and how to quickly test it with qemu.

## Copying to Installation Media

Use the excellent [Unetbootin Project](http://unetbootin.sourceforge.net/) to install your new custom Ubuntu ISO to a USB stick. Use the "Space used to preserve files across reboots" option to save configurations and files, and to not have to start over with every reboot. This is a great way to make a personal portable Ubuntu you can carry with you anywhere. Any PC or laptop made in the last 7 seven years should reliably support booting to a USB device, though you may have to enter the BIOS to allow USB booting. In many BIOS pressing the F12 key opens a boot device selector.

For making a bootable CD/DVD use the excellent K3b or Brasero. When you boot your new custom Ubuntu you'll have the option to either run it live from your boot media, or install it to a hard drive.
