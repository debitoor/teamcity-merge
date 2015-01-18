# TeamCityScript
Script for TeamCity - Lets TeamCity handle merging to master and closing github pull request

# What is this for?
The script `merge.sh` is for use in a TC commandline build step. Se below for technical details.

It is used for letting TC handle merging your pull requests to master and closing the pull request. The merge will only be done if your tests are green.

The benefits of letting TC handle merges to master are:
- You will never see a red master build because of a merge to master (tests are run before merging)
- The developer does not have to close the github pull request manually
- Attempting to merge a branch that does not correspond to a pull request will be rejected (If the developer forgot to push his/her changes to the github pull request branch)
- The developer is free to do other things, while the merge is tested and merged. He/she and others, will be notified of success or failure by github emails (watching the repo)
- This process implements an automatic queue, ensuring that only one merge is done at a time.
- This process can automatically push your changes to production if all tests are green, if you are running continuous release (optional)

# How does the developer merge to master?
Given that the developer is working in a branch called `featureX`, and this branch has been pushed to github, and a pull request has been opend for the `featureX` branch on github. All the developer has to do is:
```
git push origin featureX:ready/featureX
```

This will kick off the TC build that tries to merge the branch to master, checking that all tests are green in the process.

# How to set up the TC build that merges to master and closes the associated pull request
You need to configure a build for picking up pushes to `ready/*` branches, that merges them, runs tests and closes the associated pull request.
## General Settings
`Limit the number of simultaneously running builds (0 — unlimited)`: Set this to `1`. This effectivly creates an automate queue, making sure only one merge is done to master at a time.
## Version Control Settings
`VCS checkout mode`: Set this to `Automatically on agent (if supported by VCS root)`. We will be doing git commands in the build, so we want the git repo on the TC agent.
### VCS Roots -> Edit
`Branch specification`: To pick up pushes to `ready/*` branches we set this to:
```
-:master
+:refs/heads/ready/*
```

