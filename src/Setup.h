// What a package can't install by itself, done at launch:
//  - the Alt+Space input_server filter, which lives outside the package so a
//    package swap (an update) never pulls a loaded add-on out from under the
//    input_server;
//  - a line in UserBootscript that starts Kigo hidden at login.
#ifndef SETUP_H
#define SETUP_H

namespace Setup {

void Run();

}

#endif // SETUP_H
