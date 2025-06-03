# Account lockout policy

# Number of failed login attempts before the account is locked
net accounts /lockoutthreshold:5

# Duration (in minutes) that the account remains locked out
net accounts /lockoutduration:30

# Time window (in minutes) during which failed login attempts are counted
# If 5 failed attempts occur within this 30-minute window, the account is locked
net accounts /lockoutwindow:30
