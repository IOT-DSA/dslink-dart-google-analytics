# Google Analytics DSLink

Access Google Analytics from DSA.

## Setup

- Go to the [Google Developers Console](https://console.developers.google.com).
- Click `Create Project` and enter a project name.
- Go to the `APIs & auth` section and enable the `Analytics API` in the `APIs` section.
- Select the `Credentials` section and click `Create new Client ID`.
- Select `Installed application` and leave the `Installed application type` at `Other`.
- Click `Create Client ID`
- Copy the `Client ID` and `Client Secret` and input them into the `Add Account` action, along with an account name, and invoke the action.
- Go to the URL that is the value of the `Authorization Url` node. Authorize the application, and copy the token it gives you.
- Invoke the `Set Authorization Code` action with the copied token. You are now ready to start using the Google Analytics link.
