#!/usr/bin/env bash

/home/chaimeleon/.init/configure_sshd.sh

if [ -z "$VNC_PASSWORD" ]; then
    export VNC_PASSWORD=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-16};echo;)
    echo "VNC password random generated: $VNC_PASSWORD"
fi
echo -n "$VNC_PASSWORD" > /home/chaimeleon/.password1
x11vnc -storepasswd $(cat /home/chaimeleon/.password1) /home/chaimeleon/.password2
chmod 400 /home/chaimeleon/.password*
sed -i 's/^command=x11vnc.*/& -rfbauth \/home\/chaimeleon\/.password2/' $SUPERVISOR_CONF_FILE

if [ -n "$X11VNC_ARGS" ]; then
    sed -i "s/^command=x11vnc.*/& ${X11VNC_ARGS}/" $SUPERVISOR_CONF_FILE
fi

if [ -n "$OPENBOX_ARGS" ]; then
    sed -i "s#^command=/usr/bin/openbox\$#& ${OPENBOX_ARGS}#" $SUPERVISOR_CONF_FILE
fi

if [ -n "$RESOLUTION" ]; then
    sed -i "s/1024x768/$RESOLUTION/" /usr/local/bin/xvfb.sh
fi

USER=superset
PREVIOUS_PASSWORD=chaimeleon

if [ -z "$PASSWORD" ]; then
    export PASSWORD=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-16};echo;)
    echo "A password for user $USER random generated: $PASSWORD"
fi
echo "Changing password for the user $USER"
#echo "$USER:$PASSWORD" | chpasswd
echo -e "$PREVIOUS_PASSWORD\n$PASSWORD\n$PASSWORD" | (passwd $USER)

HOME=/home/chaimeleon
#[ -d "/dev/snd" ] && chgrp -R adm /dev/snd

sed -i -e "s|%USER%|$USER|" -e "s|%HOME%|$HOME|" $SUPERVISOR_CONF_FILE

# home folder
if [ ! -x "$HOME/.config/pcmanfm/LXDE/" ]; then
    mkdir -p $HOME/.config/pcmanfm/LXDE/
    ln -sf /usr/local/share/wallpapers/desktop-items-0.conf $HOME/.config/pcmanfm/LXDE/
fi

# Add the init script of the base image to supervisor
echo "
[program:superset]
priority=25
command=/bin/sh -c /usr/bin/run-server.sh
" >> $SUPERVISOR_CONF_FILE

# Create the connection in guacamole
if [ -n "$GUACAMOLE_USER" ]; then
    VNC_HOST_PARAM=
    if [ -n "$VNC_HOST" ]; then
        VNC_HOST_PARAM="--vnc-host $VNC_HOST"
    fi
    guacli --url $GUACAMOLE_URL --user $GUACAMOLE_USER --password $GUACAMOLE_PASSWORD --debug \
           create connection --connection-group $GUACAMOLE_USER --guacd-host $GUACD_HOST \
                             $VNC_HOST_PARAM --vnc-password $VNC_PASSWORD \
                             --sftp-user $USER --sftp-password $PASSWORD \
                             --sftp-disable-file-downloads --disable-clipboard-copy \
                             $GUACAMOLE_CONNECTION_NAME
fi

# clean up
export VNC_PASSWORD=
PASSWORD=

echo Running supervisor...
#exec /bin/tini -- supervisord -n -c /etc/supervisor/supervisord.conf
export TINI_SUBREAPER=
# we change working directory to write there the supervisor log and pid file
cd /home/chaimeleon/.supervisor
exec /bin/tini -- supervisord -n -c $SUPERVISOR_CONF_FILE
