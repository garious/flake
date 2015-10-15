#include "xpio_c.c"


#define assert(c) \
   if (!(c)) { printf(__FILE__ ":%d: assertion failed!\n", __LINE__); exit(1); }

#define eq_xx(a, b, Type, fmt, isEQ)                     \
   do {                                                  \
      Type a__ = (a);                                    \
      Type b__ = (b);                                    \
      if (!(isEQ)) {                                     \
         printf("%s:%d: assertion failed!\n"             \
                "A: " fmt "\nB: " fmt "\n",              \
                __FILE__, __LINE__, a__, b__);           \
         exit(1);                                        \
      }                                                  \
   } while (0)

#define eq_i(a,b)    eq_xx(a, b, int, "%d", a__ == b__)

// accept NULL
#define eq_str(a,b)  \
   eq_xx(a, b, const char *, "%s", \
         a__ == b__ || a__ && b__ && !strcmp(a__, b__) )



int main(int argc, char **argv)
{
   // test scanNum
   {
      const char *psz;
      unsigned n;

      psz = scanNum("123.", &n);
      eq_i(123, n);
      eq_i('.', *psz);

      psz = scanNum("123 ", &n);
      eq_i(123, n);
      eq_i(' ', *psz);

      psz = scanNum("2147483647", &n);
      eq_i(2147483647, n);
      eq_i('\0', *psz);
   }

   // test addrFromString
   {
      // Perversely, sockaddr_in keeps exposes integer values (sin_addr and
      // sin_port) as if they can be treated as numeric values, but stores
      // them in network byte order.
      struct sockaddr_in sin;
      struct sockaddr *psa = (struct sockaddr *) &sin;
      unsigned char *pby = (unsigned char *)&psa->sa_data;
      int e;

      e = addrFromString(&sin, "123.4.5.255:258");
      eq_i(0, e);
      eq_i(AF_INET, psa->sa_family);
      eq_i(1,   pby[0]);      // sin_port
      eq_i(2,   pby[1]);
      eq_i(123, pby[2]);      // sin_addr
      eq_i(4,   pby[3]);
      eq_i(5,   pby[4]);
      eq_i(255, pby[5]);

      e = addrFromString(&sin, ":123");
      eq_i(0, e);
      eq_i(AF_INET, psa->sa_family);
      eq_i(123, htons(sin.sin_port));
      eq_i(0, sin.sin_addr.s_addr);

      e = addrFromString(&sin, "1.2.3.4");
      eq_i(0, e);
      eq_i(AF_INET, psa->sa_family);
      eq_i(0, htons(sin.sin_port));
      eq_i(0x01020304, htonl(sin.sin_addr.s_addr));
   }

   return 0;
}
