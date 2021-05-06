# ACM backup and restore 

The scripts in this folder implement a _minimal_ framework built around [velero tool](https://velero.io/) to backup and restore ACM. Currently it backups/restores _only_ the managed clusters plus the needed information to register back in the restored cluster. Hence it must be restored in an already installed RHACM. 

##TL/DR

To backup ACM you should be logged in the backup you want to backup. The only parameter really neededed is the credential file which is foundamental the `aws/.credentials` file (default profile is selected).		

```
[default]
aws_access_key_id = <the aws access key id>
aws_secret_access_key =  <the aws secret access key>
```

Now running the following commnad you should backup the managed clustgers plus the strictly needed inforomation to re-register the managed clusters.

```shell
$ ./backup-acm.sh -c ,,,/awss3.credentials
```
As soon the script is finished you should be able to find the backup in the `S3` storage.


```
$ velero get backups
NAME                               STATUS            ERRORS   WARNINGS   CREATED                          EXPIRES   STORAGE LOCATION   SELECTOR
acm-backup-dario-155320-05-06-21   Completed         0        0          2021-05-06 15:53:24 +0200 CEST   29d       default            <none>
backup-acm-resources               Completed         0        0          2021-04-24 00:11:32 +0200 CEST   17d       default            <none>
backup-sre                         PartiallyFailed   4        0          2021-04-29 11:54:08 +0200 CEST   22d       default            <none>
backup-sre-to-acm                  Completed         0        0          2021-05-02 21:08:18 +0200 CEST   26d       default            <none>
backup-sre-to-acm-dario            Completed         0        0          2021-05-05 18:28:19 +0200 CEST   29d       default            <none>
backup-sre3                        Completed         0        0          2021-04-30 16:12:09 +0200 CEST   23d       default            <none>
```

Now to restore the cluster **you should point your `.kube/config` to the cluster you want restore ACM**. Running


```shell
$ ./restore-acm.sh -c ,,,/awss3.credentials
```
If no backup name is selected the `restore-acm.sh` script automatically select the most recent backup with no errors.

## Full doc

TODO

## Known issue


The `backup-acm.sh` script is (currently) not re-entrant. This is due to the fact that  internally it adds label `velero.io/exclude-from-backup=true` to few specific resource.. So it cannot be ran in parallel with other instances. In the future we may provide mitigations for this issue.