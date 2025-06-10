# Disable password expiration
net accounts /maxpwage:unlimited

# Set minimum password length and complexity
# Reduced from 8 to 7 per new requirements
net accounts /minpwlen:7
net accounts /uniquepw:5       # Optional: Prevents recent password reuse
