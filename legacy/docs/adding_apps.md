* Pretty old - Probably still a work in progress - Just getting it commited

## Adding an app to the infra

At the moment the process isn't the best... but that's the point of planning,
applying, testing, refining, re-iterating


##### Add the app name
* Make sure the app/image/container has a label
    - At the moment using the nomenclature `com.consul.service=APPNAME`
        - Need to change it to something like `com.consul.org.service` or something.
        It's important that it can apply to any domain for different environments.
        But apparently this is reverse DNS notation so....
* Add the app name to the list in `vars.tf`
* Add the app name to CloudFlare
    - At this point we are going to have to start looking into programmatically
    adding subdomain's or start operating off of path matching instead
    ie. Instead of  `app.domain.com` -> `APP_IP:PORT` via reverse proxy
    we go for   `domain.com/APP` -> `APP_IP:PORT`
    - Contiueing to use consul for routing, this should be achievable, and possibly
    a LOT less cumbersome if the path matching works great. Because instead of registering
    each subdomain for SSL (or like my case, renaming a subdomain and re-registering
    SSL certs), we just edit the path (the app needs to relabled, but thats the point)
