# Disable password expiration
net.exe accounts /maxpwage:unlimited

# Strengthen password requirements in line with security baselines
net.exe accounts /minpwlen:14     # Minimum length of 14 characters
net.exe accounts /uniquepw:24     # Remember last 24 passwords to prevent reuse
