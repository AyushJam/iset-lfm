"""
Python model for the mathematical LED flicker model described in
    "LED Flicker Modeling" by Ayush Jamdar and Ramakrishna Kakarala (August 2025)

Input:
    - D: duty cycle of the LED in [0, 1]
    - tp: time period of the LED (1/frequency) in ms
    - te: sensor exposure duration in ms
    - ts: exposure start time in ms
    - A: LED photon flux onto the sensor (per unit area per unit time)

Output:
    - phi: sensor irradiance (flux per unit area integrated over time)

Author: Ayush Jamdar (Summer Intern at OVT, 2025)
"""

import numpy as np

def get_phi(D, tp, te, ts=0, A=1, offset=0, use_random_ts=False):
    """
    Flicker Model Implementation
    All inputs must be scalars!
    offset: source intensity at OFF
    """

    if use_random_ts:
        # Get exposure start time (a random variable)
        ts = np.random.uniform(0, tp)
    
    # Derive 'to' from D and tp
    to = D * tp  # LED ON time

    # Model level I: Check duty cycle
    if D <= 0.5:
        # Model level II: Check exposure duration
        # Case 1.1
        if te <= to:
            if np.all((ts >= 0) & (ts <= (to - te))):
                phi = A * te
            elif np.all((ts > (to - te)) & (ts <= to)):
                phi = A * (to - ts)
            elif np.all((ts > to) & (ts <= (tp - te))):
                phi = 0
            elif np.all((ts > (tp - te)) & (ts < tp)):
                phi = A * (te + ts - tp)
            else:
                raise ValueError("ts={} is out of bounds for all elements".format(ts))

        # Case 1.2
        elif np.all((to < te) & (te <= (tp - to))):
            if np.all((ts >= 0) & (ts <= to)):
                phi = A * (to - ts)
            elif np.all((ts > to) & (ts <= (tp - te))):
                phi = 0
            elif np.all((ts > (tp - te)) & (ts <= (tp + to - te))):
                phi = A * (ts + te - tp)
            elif np.all((ts > (tp + to - te)) & (ts < tp)):
                phi = A * to
            else:
                raise ValueError("ts is out of bounds for all elements")
            
        # Case 1.3
        elif np.all(((tp - to) < te) & (te <= tp)):
            if np.all((ts >= 0) & (ts <= (tp - te))):
                phi = A * (to - ts)
            elif np.all((ts > (tp - te)) & (ts <= to)):
                phi = A * (to + te - tp)
            elif np.all((ts > to) & (ts <= (tp + to - te))):
                phi = A * (ts + te - tp)
            elif np.all((ts > (tp + to - te)) & (ts < tp)):
                phi = A * to
            else:
                raise ValueError("ts is out of bounds for all elements")

        # Case 1.4
        elif np.all((tp < te) & (te <= (tp + to))):
            if np.all((ts >= 0) & (ts <= (tp + to - te))):
                phi = A * (to + te - tp)
            elif np.all((ts > (tp + to - te)) & (ts <= to)):
                phi = A * (2 * to - ts)
            elif np.all((ts > to) & (ts <= (2 * tp - te))):
                phi = A * to
            elif np.all((ts > (2 * tp - te)) & (ts < tp)):
                phi = A * (to + ts - 2 * tp + te)
            else:
                raise ValueError("ts is out of bounds for all elements")

        # Case 1.5
        elif np.all(((tp + to) < te) & (te <= (2 * tp - to))):
            if np.all((ts >= 0) & (ts <= to)):
                phi = A * (2 * to - ts)
            elif np.all((ts > to) & (ts <= (2 * tp - te))):
                phi = A * to
            elif np.all((ts > (2 * tp - te)) & (ts <= (2 * tp + to - te))):
                phi = A * to + A * (ts - 2 * tp + te)
            elif np.all((ts > (2 * tp + to - te)) & (ts < tp)):
                phi = 2 * A * to
            else:
                raise ValueError("ts is out of bounds for all elements")

        # Case 1.6
        elif np.all(((2 * tp - to) < te) & (te <= 2 * tp)):
            if np.all((ts >= 0) & (ts <= (2 * tp - te))):
                phi = A * (2 * to - ts)
            elif np.all((ts > (2 * tp - te)) & (ts <= to)):
                phi = A * (2 * to + te - 2 * tp)
            elif np.all((ts > to) & (ts <= (2 * tp - te + to))):
                phi = A * (te + ts - 2 * tp + to)
            elif np.all((ts > (2 * tp - te + to)) & (ts < tp)):
                phi = 2 * A * to
            else:
                raise ValueError("ts is out of bounds for all elements")
        # if te is out of range
        else:
            te_effective = np.fmod(te, 2 * tp)
            n_2cycles = int((te - te_effective) / (2 * tp))
            phi = (2 * A * to * n_2cycles) + get_phi(
                D, tp, te_effective, ts, A, offset, use_random_ts
            )

            # offset
            phi += offset * 2 * tp * n_2cycles
            return phi

    elif D > 0.5:
        # Case 2.1
        if np.all((0 < te) & (te <= (tp - to))):
            if np.all((ts >= 0) & (ts <= (to - te))):
                phi = A * te
            elif np.all((ts > (to - te)) & (ts <= to)):
                phi = A * (to - ts)
            elif np.all((ts > to) & (ts <= (tp - te))):
                phi = 0
            elif np.all((ts > (tp - te)) & (ts < tp)):
                phi = A * (ts + te - tp)
            else:
                raise ValueError("ts is out of bounds for all elements")

        # Case 2.2
        elif np.all(((tp - to) < te) & (te <= to)):
            if np.all((ts >= 0) & (ts <= (to - te))):
                phi = A * te
            elif np.all((ts > (to - te)) & (ts <= (tp - te))):
                phi = A * (to - ts)
            elif np.all((ts > (tp - te)) & (ts <= to)):
                phi = A * (to - tp + te)
            elif np.all((ts > to) & (ts < tp)):
                phi = A * (ts + te - tp)
            else:
                raise ValueError("ts is out of bounds for all elements")

        # Case 2.3
        elif np.all((to < te) & (te <= tp)):
            if np.all((ts >= 0) & (ts <= (tp - te))):
                phi = A * (to - ts)
            elif np.all((ts > (tp - te)) & (ts <= to)):
                phi = A * (to - tp + te)
            elif np.all((ts > to) & (ts <= (to + tp - te))):
                phi = A * (ts + te - tp)
            elif np.all((ts > (to + tp - te)) & (ts < tp)):
                phi = A * to
            else:
                raise ValueError("ts is out of bounds for all elements")

        # Case 2.4
        elif np.all((tp < te) & (te <= (2 * tp - to))):
            if np.all((ts >= 0) & (ts <= (tp + to - te))):
                phi = A * (to + te - tp)
            elif np.all((ts > (tp + to - te)) & (ts <= to)):
                phi = A * (2 * to - ts)
            elif np.all((ts > to) & (ts <= (2 * tp - te))):
                phi = A * to
            elif np.all((ts > (2 * tp - te)) & (ts < tp)):
                phi = A * (ts - 2 * tp + te + to)
            else:
                raise ValueError("ts is out of bounds for all elements")
            
        # Case 2.5
        elif np.all(((2 * tp - to) < te) & (te <= (tp + to))):
            if np.all((ts >= 0) & (ts <= (tp + to - te))):
                phi = A * (to + te - tp)
            elif np.all((ts > (tp + to - te)) & (ts <= (2 * tp - te))):
                phi = A * (2 * to - ts)
            elif np.all((ts > (2 * tp - te)) & (ts <= to)):
                phi = A * (2 * to + te - 2 * tp)
            elif np.all((ts > to) & (ts < tp)):
                phi = A * (to + ts + te - 2 * tp)
            else:
                raise ValueError("ts is out of bounds for all elements")

        # Case 2.6
        elif np.all(((tp + to) < te) & (te <= 2 * tp)):
            if np.all((ts >= 0) & (ts <= (2 * tp - te))):
                phi = A * (2 * to - ts)
            elif np.all((ts > (2 * tp - te)) & (ts <= to)):
                phi = A * (2 * to + te - 2 * tp)
            elif np.all((ts > to) & (ts <= (2 * tp + to - te))):
                phi = A * (to + ts + te - 2 * tp)
            elif np.all((ts > (2 * tp + to - te)) & (ts < tp)):
                phi = 2 * A * to
            else:
                raise ValueError("ts is out of bounds for all elements")

        # te is larger than 2tp
        else:
            te_effective = np.fmod(te, 2 * tp)
            n_2cycles = te - te_effective
            phi = (2 * A * to * n_2cycles) + get_phi(
                D, tp, te_effective, ts, A, offset, use_random_ts
            )

            # offset
            phi += offset * 2 * tp * n_2cycles
            return phi
    else:
        raise ValueError("D can only lie in (0, 1)!")

    # Account for offset
    phi += offset * te
    return phi


def phi_over_frames(D, fp, te, ts, frame_rate, Nsec, A=1, offset=0):
    tp = 1000 / fp
    tf = (1 / frame_rate) * 1000  # we're using ms as time unit
    # N second video feed
    N = Nsec
    time = np.linspace(0, N, int(frame_rate * N))  # this is in seconds
    phi_t = np.zeros_like(time)
    ts_arr = np.zeros_like(time)

    for i, t in enumerate(time):
        if i > 0:
            # get phi for that frame
            phi_t[i] = get_phi(D, tp, te, ts, A, offset)

            # update ts for the next frame
            ts_arr[i] = ts

            ts = np.fmod((ts + tf), tp)

    return time, phi_t
