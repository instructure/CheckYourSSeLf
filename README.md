CheckYourSSeLf
==============
A friendly [Slack](https://slack.com/) bot that checks your Amazon AWS accounts, and remote urls for expiring SSL certificates.

How does it work?
-----------------
* The bot retrieves a list of all IAM Server Certificates from each configured AWS account, and each remote url.
* Every certificate is then parsed to see how many days are left until expiration.
* Certificates that fall below the configured warning threshold will trigger an alert.
* The results get posted to Slack.

How do I use it?
----------------
1. Clone this repository.
2. Create a copy of the sample configuration file and modify it to suit your needs.
   * `cp config.yml.sample config.yml`
   * `text-editor-of-your-choice config.yml`
3. Choose a home for the bot, and copy it there. Ruby and Bundler are the only requirements.
   * `ssh deploy@slackbot-server 'mkdir -p /opt/checkyoursself'`
   * `scp CheckYourSSeLf.rb config.yml Gemfile Gemfile.lock deploy@slackbot-server:/opt/checkyoursself`
4. Install the bundle.
   * `ssh deploy@slackbot-server 'cd /opt/checkyoursself && bundle install --deployment'`
5. Run the bot once to make sure everything is working properly.
   * `ssh deploy@slackbot-server 'cd /opt/checkyoursself && ruby CheckYourSSeLf.rb'`
6. Set up a crontab entry to run the bot on a regular basis.
   * `ssh deploy@slackbot-server`
   * `crontab -e`
     * A line like this would make the bot run once a day at 16:05:

       `5 16 * * * cd /opt/checkyoursself && ruby CheckYourSSeLf.rb`
7. That's it. No more surprises!

LICENSE
-------
The MIT License (MIT)

Copyright (c) 2015-2016 Instructure, Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
