#!/bin/bash

## TODO: Turn into a rails scipt
## https://docs.gitlab.com/ee/administration/operations/rails_console.html
exit;

## Below steps are run inside a rails console
## https://docs.gitlab.com/ee/user/project/settings/project_access_tokens.html#create-a-group-access-token

`sudo gitlab-rails console`

## Create token
admin = User.find(1) # group admin
group = Group.find(1) # the group you want to create a token for
bot = Users::CreateService.new(admin, { name: 'group_token', username: "group_#{group.id}_bot", email: "group_#{group.id}_bot@example.com", user_type: :project_bot }).execute # create the group bot user
# for further group access tokens, the username should be group_#{group.id}_bot#{bot_count}, e.g. group_109_bot2, and their email should be group_109_bot2@example.com
bot.confirm # confirm the bot
group.add_user(bot, :maintainer) # add the bot to the group at the desired access level
token = bot.personal_access_tokens.create(scopes:[:read_api], name: 'group_token') # give it a PAT
gtoken = token.token # get the token value


## Revoke token
bot = User.find_by(username: 'group_109_bot') # the owner of the token you want to revoke
token = bot.personal_access_tokens.last # the token you want to revoke
token.revoke!
