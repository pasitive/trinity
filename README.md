trinity
=======

Trinity - an automated assistant working with Redmine.
The basic idea is to save people from manual operations status changes, translation problems, etc. during the task.

Highlights:
Transition - the process of moving tasks from state to state.
Each task takes a certain cycle: production, decomposition, implementation, testing, commissioning.
You can enable or disable certain transitions in the configuration file.

The basic workflow:

There are 2 types of tasks: Task and error.
The task - contains the logic of work and requires verification manager.
Error - corrected by the developer and immediately goes to QA.

Standard cycle:
The manager sets the task. The task assigned to the developer.
The developer sets the status - Fixed.
QA department then checks the task in a special environment called shot.
Shot of the task falls to build (set shots).
If everything is OK in build, the task goes to production.

Fixed--[auto]-->In shot--[QA]-->In shot - OK--[auto]-->[On prerelease]--[QA]-->On prerelease - OK--[auto]-->Closed

Installation:

Gemfile:
---
source 'https://rubygems.org'
gem 'trinity', :git => 'git@github.com:pasitive/trinity.git', :tag => '1.1.0'
gem 'god'
---

1. Create working directory
> mkdir trinity
> cd trinity

2. Use RVM
> rvm use 1.9.3@trinity --rvmrc --create
> cd ..
> cd trinity
> bundle install
Read following notes.

3. git clone git@github.com:<yourname>/<yourproject>.git

4. Edit transition.god & config.yaml

5. rvmsudo god load -c transition.god
