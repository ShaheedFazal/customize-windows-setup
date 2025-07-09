# Disable password expiration
net.exe accounts /maxpwage:unlimited

# Set minimum password length and complexity
# Reduced from 8 to 7 per new requirements
net.exe accounts /minpwlen:7
net.exe accounts /uniquepw:5       # Optional: Prevents recent password reuse
