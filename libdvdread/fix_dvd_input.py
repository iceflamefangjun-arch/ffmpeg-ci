import re, subprocess, os

srcdir = '/home/dev-arm/.cache/shplayer/ffmpeg-src/libdvdread'
filepath = srcdir + '/src/dvd_input.c'

# Reset to 6.1.3 first
subprocess.run(['git', '-C', srcdir, 'reset', '--hard', '6.1.3'], check=True)

with open(filepath) as f:
    content = f.read()

# Step 1: Remove unconditional #include <unistd.h>
content = re.sub(r'^#include <unistd\.h>[^\n]*\n', '', content, flags=re.MULTILINE)

# Step 2: Add io.h + else + unistd.h  inside the #ifdef _WIN32 block
old_str = '#include "../msvc/contrib/win32_cs.h"\n#endif'
new_str = '#include <io.h>\n#include "../msvc/contrib/win32_cs.h"\n#else\n#include <unistd.h>                              /* lseek */\n#endif'
assert old_str in content, "pattern not found!"
content = content.replace(old_str, new_str, 1)

with open(filepath, 'w') as f:
    f.write(content)

print('done - verifying:')
lines = content.splitlines()
for i, l in enumerate(lines[22:36], start=23):
    print(f'{i}: {repr(l)}')
