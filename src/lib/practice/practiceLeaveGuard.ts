export type PracticeLeaveGuard = () => Promise<boolean>;
export type RegisterPracticeLeaveGuard = (guard: PracticeLeaveGuard) => () => void;

export interface PracticeLeaveGuardCoordinator {
  register: RegisterPracticeLeaveGuard;
  requestSelection: (action: () => void | Promise<void>) => Promise<boolean>;
  invalidate: () => void;
}

/**
 * Keeps one mounted player's leave guard and gates score changes for that player.
 * The coordinator is created per PersonalPractice instance; it has no module state.
 */
export function createPracticeLeaveGuardCoordinator(): PracticeLeaveGuardCoordinator {
  let registrationSequence = 0;
  let selectionSequence = 0;
  let current: { id: number; guard: PracticeLeaveGuard } | null = null;
  let pending: { registrationId: number; result: Promise<boolean> } | null = null;

  const register: RegisterPracticeLeaveGuard = (guard) => {
    const registration = { id: ++registrationSequence, guard };
    current = registration;
    let released = false;
    return () => {
      if (released) return;
      released = true;
      if (current?.id === registration.id) current = null;
    };
  };

  async function requestSelection(action: () => void | Promise<void>): Promise<boolean> {
    const requestId = ++selectionSequence;
    const registration = current;
    if (registration) {
      let result: Promise<boolean>;
      if (pending?.registrationId === registration.id) {
        result = pending.result;
      } else {
        const pendingResult = Promise.resolve()
          .then(() => registration.guard())
          .then((allowed) => current?.id === registration.id && allowed === true)
          .catch(() => false)
          .finally(() => {
            if (pending?.result === pendingResult) pending = null;
          });
        pending = { registrationId: registration.id, result: pendingResult };
        result = pendingResult;
      }
      const allowed = await result;
      if (!allowed || requestId !== selectionSequence || current?.id !== registration.id) return false;
    } else if (requestId !== selectionSequence) {
      return false;
    }

    await action();
    return requestId === selectionSequence;
  }

  return {
    register,
    requestSelection,
    invalidate: () => { selectionSequence++; },
  };
}
