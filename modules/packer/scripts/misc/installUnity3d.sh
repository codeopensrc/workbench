#!/bin/bash

UNITY_VER="2020.2.7f1"
CHANGE_SET="c53830e277f1"
MACHINE_ID="d123a74b29b9bf96fd5e8cd560483aeb"

#UNITY_VER="2020.3.1f1"
#CHANGE_SET="77a89f25062f"

while getopts "c:m:v:y" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        c) CHANGE_SET=$OPTARG;;
        m) MACHINE_ID=$OPTARG;;
        v) UNITY_VER=$OPTARG;;
        y) FILE_UPLOADED=true;;
    esac
done

YEAR=$(echo $UNITY_VER | cut -d "." -f 1)

UNITY_EXECUTABLE="$HOME/Unity/Hub/Editor/$UNITY_VER/Editor/Unity"
SANDBOX_ARG=""

echo "SANDBOX_ARG is?: ${SANDBOX_ARG}"
echo "User: $(whoami)"
if [ "$(whoami)" = "root" ]; then
        SANDBOX_ARG="--no-sandbox"
fi
echo "SANDBOX_ARG is now?: ${SANDBOX_ARG}"


echo "==== Start dl packages ===="
sudo apt-get -q update \
    && apt-get -q install -y --no-install-recommends apt-utils \
    && apt-get -q install -y --no-install-recommends --allow-downgrades \
    ca-certificates \
    libasound2 \
    libc6-dev \
    libcap2 \
    libgconf-2-4 \
    libglu1 \
    libgtk-3-0 \
    libncurses5 \
    libnss3 \
    libxtst6 \
    libxss1 \
    cpio \
    lsb-release \
    xvfb \
    xz-utils \
    atop \
    zenity \
    && apt-get clean

# Think these are needed for webgl builds along with zenity
sudo apt-get -q update \
    && apt-get -q install -y --no-install-recommends --allow-downgrades \
    ffmpeg \
    python \
    python-setuptools \
    build-essential \
    clang \
    libnotify4 \
    libunwind-dev \
    libssl1.0  \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*


cat > /etc/asound.conf <<EOF
pcm.!default {
  type plug
  slave.pcm "null"
}
EOF

echo "==== Done with packages ===="

###! Download
echo "==== Start downloading ===="
wget https://public-cdn.cloud.unity3d.com/hub/prod/UnityHub.AppImage
chmod +x UnityHub.AppImage
echo "==== Done downloading ===="

###! Accept EULA for Unity Hub
echo "==== Accepting eula ==== "
mkdir -p "$HOME/.config/Unity Hub"
touch "$HOME/.config/Unity Hub/eulaAccepted"
echo "==== Accepted eula ===="


##########################
# Might have to do this (good idea to anyway)
# && unity-hub install-path --set "${UNITY_PATH}/editors/" \
#########################


###! Install an editor
###! Linux Build: -m linux-mono
###! WebGL Build: -m webgl
###! Windows Build: -m windows
###! WindowsMono Build: -m windows-mono
###! childModules: --cm
echo "==== Installing editor ===="
xvfb-run ./UnityHub.AppImage --headless install --version $UNITY_VER --changeset $CHANGE_SET -m webgl -m windows-mono --cm ${SANDBOX_ARG}
echo "==== Installed editor ===="

###! Create license for server
if [[ "$FILE_UPLOADED" = true ]]; then
## Not sure how this affects the system as a whole but build server should be 100% disposable
    echo "== Inserting provided machine id to match license file"
    echo "$MACHINE_ID" > /etc/machine-id && mkdir -p /var/lib/dbus/ && ln -sf /etc/machine-id /var/lib/dbus/machine-id
else
    echo "==== Creating license file ===="
    $UNITY_EXECUTABLE -batchmode -nographics -createManualActivationFile -logfile activate1.txt
    ### Outputs in dir as Unity_v${UNITY_VER}.alf
    cat $(pwd)/Unity_v${UNITY_VER}.alf
    echo "== New license file output to $(pwd)/Unity_v${UNITY_VER}.alf"
    echo "== Also output to console above to possibly copy/paste"
    echo "== If file is not there see 'activate1.txt' for log output"

    ### Upload, answer questions, and download unity licnese file from: https://license.unity3d.com/manual
    echo "== Upload Unity_v${UNITY_VER}.alf to https://license.unity3d.com/manual"
    echo "== Answer the questions and download the license file."
    echo "== Place the Unity_v${YEAR}.x.ulf file in this directory: $(pwd)"
    echo "== and press Y to continue"

    ### Upload Unity_v2020.x.ulf to remote server
    echo "== Answer Y once file is uploaded or N to stop/exit the script"
    echo "TODO: Auto detect .ulf file in current directory"

    while true
    do
        read -r -p "File uploaded?? [Y/n] " input

        case $input in
            [yY][eE][sS]|[yY]) echo "Continuing"
            break
            ;;
            [nN][oO]|[nN]) echo "Exiting"; exit;
            break
            ;;
            *) echo "Invalid input..."
            ;;
        esac
    done
fi

###! Attempt to activate unity license file
echo "==== Activating Unity with uploaded .ulf file"
$UNITY_EXECUTABLE -batchmode -nographics -manualLicenseFile Unity_v${YEAR}.x.ulf -logfile activate2.txt
echo "==== Below is output from license activation attempt:"
cat activate2.txt
echo "==== Done activating! Hopefully it worked."
echo "==== If unsuccessful see above or 'activate2.txt' for log output"


###! Move Unity to globally accessable path (or configure install path correctly)
mv $HOME/Unity /opt/Unity
###! TODO: Test if only changing group (chgrp) would be enough
chown -R gitlab-runner:gitlab-runner /opt/Unity
mkdir -p /home/gitlab-runner/.local/share
cp -r /root/.local/share/unity3d /home/gitlab-runner/.local/share/unity3d
chown -R gitlab-runner:gitlab-runner /home/gitlab-runner/.local/share/unity3d

