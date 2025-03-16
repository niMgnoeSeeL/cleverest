(assert (str.in_re "0" ((_ re.loop 0 1) ((_ re.loop 0 1) (str.to_re "1")))))
(check-sat)
