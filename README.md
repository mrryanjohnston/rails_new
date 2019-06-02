# rails_new: A Buildable, Bakable and Deployable Rails Project

This is an accompanying repository for my blog posts:
1. [Turning Your Application into an Installable Package](https://ryjo.codes/articles/turning-your-application-into-an-installable-package.html).

## Building

You can build and install this rails application on your Debian-based distro by
doing this:

```
git clone git@github.com:mrryanjohnston/rails_new.git
cd rails_new
bin/rails credentials:edit
debuild --no-tgz-check
cd ..
sudo dpkg -i rails-new_0.0.0_all.deb
```

## Deploying to AWS

*WARNING*: These scripts will spin up AWS infrastructure that cost money.

*ANOTHER WARNING*: These scripts are a little flaky. You should read through
them first to figure out what they're doing :)

In order to deploy this application to AWS, you must first create an AMI from
which you will build environment-specific AMIs:

```
./lib/scripts/create_template.sh
```

This will create an AMI on AWS called `rails-new-template`. Before you attempt
to use this AMI, it needs to get out of `pending` state. You can check the
status of all the artifacts created with the `create_template.sh` script by
doing the following:

```
./lib/scripts/status_template.sh
```

Once the status of the AMI is `available`, you can clean up the artifacts that
are no longer necessary for building environment-specific AMIs:

```
./lib/scripts/post_create_template.sh
```

You should do this because otherwise you'll be charged money for the running
instance the `create_template.sh` script starts up. Running the
`status_template.sh` script should show you that everything was terminated
except for the AMI.

Now we can create an environment-specific AMI and initialize the
infrastructure. The default environment is `production` which will deploy a
running rails application to `rails-new.ryjo.codes`:

```
./lib/scripts/create_environment.sh
```

If you want to create an environment called `feature-123` that would be
available at `rails-new-feature-123.ryjo.codes` instead, you could do the
following:

```
./lib/scripts/create_environment.sh "feature-123"
```

This script is a little flaky, and it might fail when trying to ssh into the
running instance. If this does, no worries: you can run the
`create_environment.sh` script again. It'll detect which pieces of AWS
infrastructure have already been built and use those.

You can check the status of these pieces of infrastructure by doing this:

```
./lib/scripts/status_environment.sh "feature-123"
```

It may take a few minutes while the route53 DNS record propogates, but,
eventually, you should be able to get to
`http://rails-new-feature-123.ryjo.codes`
in your browser.

You can deploy new versions of your application by doing this:

```
./lib/scripts/deploy.sh "feature-123"
```

Again, you'll need to wait for DNS to propogate. Once it does, you can spin down
the old ec2 instances that are no longer being referenced by the DNS entry:

```
./lib/scripts/prune_environment.sh "feature-123"
```

You can spin down this environment and all of its pieces of infrastructure by
doing this:

```
./lib/scripts/delete_environment.sh "feature-123"
```

Similarly, you can kill the template AMI by doing this:

```
./lib/scripts/delete_template.sh
```

## TODO

- Deploying to an instance behind an ELB
- Scaling up or down the amount of instances behind an ELB
