# rails_new: An Example Rails Projects that can be Bundled with dpkg

This is an accompanying repository for my blog post
[Turning Your Application into an Installable Package](https://ryjo.codes/articles/turning-your-application-into-an-installable-package.html).

## Quick Start

```
git clone git@github.com:mrryanjohnston/rails_new.git
cd rails_new
bin/rails credentials:edit
debuild --no-tgz-check
cd ..
sudo dpkg -i rails-new_0.0.0_all.deb
```
