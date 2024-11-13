FROM ubuntu:noble
ENV TRAC_ADMIN_NAME="trac_admin"
ENV TRAC_ADMIN_PASSWD="passw0rd"
ENV TRAC_PROJECT_NAME="trac_project"
ENV TRAC_DIR="/var/local/trac"
ENV TRAC_INI="$TRAC_DIR/conf/trac.ini"
ENV DB_LINK="sqlite:db/trac.db"
EXPOSE 8123

RUN apt-get update && apt-get install -y apache2 libapache2-mod-wsgi-py3 pipx && apt-get -y clean
# Apache/mod_wsgi runs as www-data user, which doesn't have permission to read files in /root/
# Trac 1.6 install in location accessible by www-data
RUN mkdir -p /opt/trac
RUN PIPX_HOME=/opt/trac/.pipx PIPX_BIN_DIR=/usr/local/bin pipx install Babel
RUN PIPX_HOME=/opt/trac/.pipx PIPX_BIN_DIR=/usr/local/bin pipx install Trac
RUN chown -R www-data:www-data /opt/trac

RUN mkdir -p $TRAC_DIR
RUN trac-admin $TRAC_DIR initenv $TRAC_PROJECT_NAME $DB_LINK
RUN trac-admin $TRAC_DIR deploy /tmp/deploy
RUN mv /tmp/deploy/* $TRAC_DIR
RUN htpasswd -b -c $TRAC_DIR/.htpasswd $TRAC_ADMIN_NAME $TRAC_ADMIN_PASSWD
RUN trac-admin $TRAC_DIR permission add $TRAC_ADMIN_NAME TRAC_ADMIN

# Adjusted permissions
RUN chown -R www-data:www-data $TRAC_DIR
RUN chmod -R 775 $TRAC_DIR

RUN echo "Listen 8123" >> /etc/apache2/ports.conf

# Apache config 
RUN echo '<VirtualHost *:8123>\n\
    ServerName localhost\n\
    DocumentRoot /var/local/trac/htdocs/\n\
    \n\
    LogLevel info\n\
    ErrorLog /var/log/apache2/error.log\n\
    CustomLog /var/log/apache2/access.log combined\n\
    \n\
    WSGIScriptAlias / /var/local/trac/cgi-bin/trac.wsgi\n\
    WSGIDaemonProcess trac user=www-data group=www-data python-path=/opt/trac/.pipx/venvs/trac/lib/python3.12/site-packages:/var/local/trac\n\
    WSGIProcessGroup trac\n\
    WSGIApplicationGroup %{GLOBAL}\n\
    \n\
    <Directory /var/local/trac/cgi-bin>\n\
        Require all granted\n\
        SetHandler wsgi-script\n\
    </Directory>\n\
    \n\
    <Location />\n\
        AuthType Basic\n\
        AuthName "'"$TRAC_PROJECT_NAME"'"\n\
        AuthUserFile /var/local/trac/.htpasswd\n\
        Require valid-user\n\
    </Location>\n\
</VirtualHost>' > /etc/apache2/sites-available/trac.conf

RUN a2enmod headers wsgi
RUN a2dissite 000-default
RUN a2ensite trac.conf
CMD ["apache2ctl", "-D", "FOREGROUND"]