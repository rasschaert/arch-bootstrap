arch-bootstrap
==============

Shell script that bootstraps an Arch Linux installation.

###Unsafe Usage
```
curl https://raw.githubusercontent.com/rasschaert/arch-bootstrap/master/bootstrap.bash | bash
```

Piping curl to a shell is of course a [bad idea](http://blog.existentialize.com/dont-pipe-to-your-shell.html), but #YOLO ```¯\_(ツ)_/¯```


###Safe Usage
It's advisable to find a more secure way to get the script onto the installer.

One suggestion is to use the SSH server included in the installer, that can be start with ```systemctl start sshd```. After that you can set a root password and ```scp``` the script in.
