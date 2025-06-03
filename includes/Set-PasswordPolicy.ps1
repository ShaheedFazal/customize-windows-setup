# Disable password expiration
net accounts /maxpwage:unlimited

# Set minimum password length and complexity
net accounts /minpwlen:8
net accounts /uniquepw:5       # Optional: Prevents recent password reuse
