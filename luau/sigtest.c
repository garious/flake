// Simple test to validate signal handling capabilites on a platform.
// (For example, waitid() seeems to be broken on OSX.)

#define _POSIX_C_SOURCE 200809
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <sys/wait.h>


static pid_t try_waitid(const char *where)
{
   siginfo_t si;
   int e;
   memset(&si, 0, sizeof si);

   e = waitid(P_ALL, 0, &si, WEXITED | WNOHANG);

   if (e == -1) {
      printf("%s: waitid() error (%d: %s)\n", where, errno, strerror(errno));
      return 0;
   } else if (e != 0) {
      printf("%s: unexpected return value from waitid: %d\n", where, e);
      return 0;
   } else if (si.si_pid == 0) {
      // With WNOHANG, e==0 could mean "wouldblock" *or* success.
      // In wouldblock case, it sets si_pid to 0. In succes case, it
      // presumably sets it to non-zero.
      // http://pubs.opengroup.org/onlinepubs/9699919799/functions/waitid.html
      printf("%s: waitid() would block...\n", where);
      return 0;
   }

   printf("%s: reaped %d with waitid()\n", where, si.si_pid);
   return si.si_pid;
}


static pid_t try_waitpid(const char *where)
{
   pid_t pid = waitpid(-1, NULL, WNOHANG);
   if (pid == 0) {
      printf("%s: waitpid() would block...\n", where);
      return 0;
   }
   if (pid < 0) {
      printf("%s: waitpid() returned error (%s)\n", where, strerror(errno));
      return 0;
   }
   printf("%s: reaped %d with waitpid()\n", where, pid);
   return pid;
}


static void handleCHLD(int signum, siginfo_t *psi, void *pv)
{
   pid_t pid;
   printf("Handler: signum=%d signo=%d pid=%d status=%d\n",
          signum, psi->si_signo, psi->si_pid, psi->si_status);

   pid = try_waitid("Handler");
   if (pid != psi->si_pid) {
      printf("Handler: waitid() apparently not working\n");
      (void) try_waitpid("Handler");
   }

   printf("Handler: exiting.\n");
}


int main(int argc, char **argv)
{
   struct sigaction sa = {0};
   struct sigaction osa = {0};
   sigset_t ss, oss;
   int n;

   printf("Starting...\n");
   // register SIGCHLD handler
   sa.sa_sigaction = handleCHLD;
   sa.sa_flags = SA_SIGINFO;

   if (sigaction(SIGCHLD, &sa, &osa)) {
      printf("sigaction failed: %d (%s)\n", errno, strerror(errno));
   }

   // block SIGCHLD

   sigemptyset(&ss);
   sigaddset(&ss, SIGCHLD);
   sigprocmask(SIG_BLOCK, &ss, &oss);

   // spawn some child processes

   for (n=1; n<=3; ++n) {
      int pid;
      if ( (pid=fork()) == 0) {
         printf("Child %d exiting...\n", n);
         exit(n);
      }
      printf("Spawned %d\n", pid);
   }

   sleep(1);

   // unblock SIGCHLD

   sigprocmask(SIG_UNBLOCK, &ss, &oss);

   // see if any children left un-reaped

   (void) try_waitpid("Outside");
   (void) try_waitid("Outside");

   return 0;
}
