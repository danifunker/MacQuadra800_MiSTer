#ifndef CPU_DISPATCH_OBSERVER_H
#define CPU_DISPATCH_OBSERVER_H

// Call once after every rising-edge eval, including reset and periods when
// all consumers are disabled. First observation establishes a baseline;
// reset observations resynchronize without manufacturing opcode events.
class CpuDispatchObserver {
public:
	bool sample(bool reset, bool toggle) {
		const bool event = valid_ && !reset && toggle != last_;
		last_ = toggle;
		valid_ = true;
		return event;
	}
private:
	bool valid_ = false;
	bool last_ = false;
};

// Preserve the existing profiler's sampled bracket semantics: start clears
// counters and includes this sample; stop excludes this sample. If both
// requests are pending together, start wins. Requests wait through reset.
class CpuProfileGate {
public:
	enum Action { Skip, Start, Count, Stop };
	Action sample(bool start, bool stop) {
		if (start) { active_ = true; return Start; }
		if (stop) {
			const bool was_active = active_;
			active_ = false;
			return was_active ? Stop : Skip;
		}
		return active_ ? Count : Skip;
	}
	bool active() const { return active_; }
	void stop() { active_ = false; }
private:
	bool active_ = false;
};

#endif
