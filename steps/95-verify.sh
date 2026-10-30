# desc: Health check of the finished setup (same as ./setup.sh doctor)
# always: yes

run_doctor || warn "Some health checks failed (above). Try: ./setup.sh doctor --fix"
