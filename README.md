# teamcity-merge
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

NOTE: We wrote a commmand line tool that helps you, and makes things even easier for the developer: [tcmerge](https://github.com/e-conomic/tcmerge)



# How to set up the TC build that merges to master and closes the associated pull request
You need to configure a build for picking up pushes to `ready/*` branches, that merges them, runs tests and closes the associated pull request. The following sections describes the setting you need on your merge-TC build.

## General Settings
`Limit the number of simultaneously running builds (0 — unlimited)`: Set this to `1`. This effectivly creates an automated queue, making sure only one merge is done to master at a time.

## Version Control Settings
`VCS checkout mode`: Set this to `Automatically on agent (if supported by VCS root)`. We will be doing git commands in the build, so we want the git repo on the TC agent.

### VCS Roots -> Edit

`Default branch`: Set this to `master`

`Branch specification`: To pick up pushes to `ready/*` branches we set this to:
```
+:refs/heads/ready/*
```

## Build steps

1. The first build step you add should be a Command Line build step. We will call it `Merge ready branch into master`. In this step you copy the script from `merge.sh` from this reposiotry.
2. The next build steps should run all your tests and verifications you want to run on your codebase. You normal master build.
3. The next build step you add should be a Command Line build step. We will call it `Push changes to master`. And it will contail a single line: `git push origin master`.
4. This next build step could be push to production, if you are running Continuous Release. This step is optional.
5. The final step should be a Command Line build step. We will call it `Delete ready branch (Always run)`. You should set this step to always run, even if the previous steps failed. It will contain a single line: `git push origin ":ready/%env.branch%"`. 

## Triggers -> Add new trigger rule
`Branch filter`: We do not want to trigger the build on commits to master, so we set this to:
```
+:*
-:<default>
```

## Parameters
You should add a parameter to the build

`Name`: `env.branch`

`Kind`: `Environment variable (env.)`

`Value`: `%teamcity.build.branch%`

