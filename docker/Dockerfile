FROM debian:bookworm

# Install Debian / Openembedded / Buildroot dependencies.
RUN apt-get update
RUN apt-get -y upgrade
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y software-properties-common
RUN apt-get install -y build-essential \
    byobu curl git htop man unzip vim wget \
    fakeroot fakechroot vim ssh subversion git autoconf automake groff libtool

RUN apt-get install -y \
    debhelper sshpass ccache pkg-config gawk smbclient whois syslinux genisoimage dosfstools \
    p7zip-full texinfo gawk diffstat chrpath socat libsdl1.2-dev xterm kmod libssl-dev \
    bc sudo \
    cpio bzip2 xz-utils iputils-ping gperf \
    libncurses5-dev rsync flex bison lzop zstd liblz4-tool \
    debootstrap multistrap dh-make binfmt-support qemu-user-static jq \
    gdisk

RUN apt-get install -y strace grub-efi-amd64-bin

RUN apt-get install -y locales && \
 echo "LC_ALL=en_US.UTF-8" >> /etc/environment && \
 echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && \
 echo "LANG=en_US.UTF-8" > /etc/locale.conf && \
 locale-gen en_US.UTF-8
 
# default bash instead of dash
RUN \
    echo "dash dash/sh boolean false" | debconf-set-selections && \
    DEBIAN_FRONTEND=noninteractive dpkg-reconfigure --priority critical dash
 
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.en
ENV LC_ALL en_US.UTF-8

ARG USER_ID=1000
# create a user
ARG USER=user

RUN useradd -ms /bin/bash -u $USER_ID -G sudo $USER
# Add bashrc that exports locales required by python (for bitbake)
ADD docker-scripts/bashrc /home/user/.bashrc
ADD docker-scripts/user.sudo etc/sudoers.d/sudouser

USER $USER
ENV HOME /home/$USER
WORKDIR /home/$USER
CMD ["bash"]
 
