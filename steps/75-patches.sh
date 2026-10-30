# desc: Re-apply the small fixes Omarchy needs to run from your home folder
# always: yes

# Each patch checks itself: is it still needed, is it already in, does the
# code it changes still exist. A patch that no longer fits is reported, not forced.
apply_patches || warn "Not every patch could be applied (see above). The desktop still works; the affected feature may misbehave until the patch is updated."
