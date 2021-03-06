An Introduction to Writing Modulefiles
======================================

This is a different kind of introduction to Lmod.  Here we will remind
you what Lmod is doing to change the environment via modulefiles.
Then we will start with the four functions that are typically needed
for any modulefile. From there we will talk about intermediate level
module functions when things get more complicated.  Finally we will
discuss the advanced module functions to flexibly control your site
via modules.  All the Lua module functions available are described in
:ref:`lua_modulefile_functions-label` which can be useful as a
reference.  This discussion to show how these functions can be used.


A Reminder of what Lmod is doing
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

All Lmod is doing is changing the environment.  Suppose you want to
use the "ddt" debugger installed on your system which is made
available to you via the module.  If you try to execute ddt without
the module loaded you get::

   $ ddt
   bash: command not found: ddt

   $ module load ddt
   $ ddt

After the ddt module is loaded, executing **ddt** now works.  Let's
remind ourselves why this works.  If you try checking the environment
before loading the ddt modulefile::

   $ env | grep -i ddt
   $ module load ddt
   $ env | grep -i ddt

   DDTPATH=/opt/apps/ddt/5.0.1/bin
   LD_LIBRARY_PATH=/opt/apps/ddt/5.0.1/lib:...
   PATH=/opt/apps/ddt/5.0.1/bin:...

   $ module unload ddt
   $ env | grep -i ddt
   $


The first time we check the environment we find that there is no
**ddt** stored there.  But the second time there we see that the PATH,
DDTPATH and LD_LIBRARY_PATH have been modified.  Note that we have
shortened the path-like variables to show the important changes.  After
unloading the module all the references for ddt have been removed. We
can see what the modulefile looks like by doing::

   $ module show ddt

   help([[
   For detailed instructions, go to:
      https://...

   ]])
   whatis("Version: 5.0.1")
   whatis("Keywords: System, Utility")
   whatis("URL: http://content.allinea.com/downloads/userguide.pdf")
   whatis("Description: Parallel, graphical, symbolic debugger")

   setenv(       "DDTPATH",        "/opt/apps/ddt/5.0.1/bin")
   prepend_path( "PATH",           "/opt/apps/ddt/5.0.1/bin")
   prepend_path( "LD_LIBRARY_PATH","/opt/apps/ddt/5.0.1/lib")

Modulefiles are written in the positive.  Namely, the functions used
say **setenv**, set this environment variable to have this
value) or **prepend_path**, prepend to this path like variable with
this value.  When the modulefile is loaded the functions add to the
environment.  When a modulefile is unloaded the functions are
reversed. So the **setenv** unset the environment variable and the
**prepend_path** removes the value from the path like variable.


Basic Modulefiles
^^^^^^^^^^^^^^^^^

There are two main module functions, namely **setenv** and
**prepend_path**, to set the environment variables necessary to make a
package available. There are also two functions to provide
documentation, **help** and **whatis**.  The modulefile for ddt shown
above contains all the basics required to create a modulefile.

Suppose you are writing this module file for ddt version 5.0.1 and you
are placing it in the standard location for your site, namely
*/apps/modulefiles* and this directory is already in **MODULEPATH** 
(See :ref:`modulepath-label` for a discussion of how **MODULEPATH** works)
Then in the directory */apps/modulefiles/ddt* you create a file called
*5.0.1.lua* which contains the modulefile shown above.


This is the typical way of setting a modulefile up.  Namely the
package name is the name of the directory, *ddt*, and version name,
*5.0.1* is the name of the file with the *.lua* extension added.  We
add the lua extension to all modulefile written in Lua.  All
modulefiles without the lua extension are assumed to be written in
TCL.

If another version of ddt becomes available, say *5.1.2* we create
another file called *5.1.2.lua* to become the new modulefile for the
new version of *ddt*.

When a user does *module help ddt*, the arguments to the **help** function
are written out to the user.  The **whatis** function provides a way
to describe the function of the application or library.  This data can
be use by search tools such as **module keyword** *search_words*.
Here at TACC we also use that data to provide search capability via
the web interface to modules we provide.


Intermediate Level Modulefiles
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

The four basic functions describe above is all that is necessary for
the majority of modulefiles for application and libraries.  The
intermediate level is designed to describe some situations that come
up as you need to provide more than just package modulefiles but need
to set up a system.


Meta Modules
------------

Some sites create a single module to a default set of modules for all
users to start from.   This is typically called a meta module because
it loads other modules.  As an example of that, we here at TACC
have created the TACC module to provide a default compiler, mpi stack
and other modules.  Note that ``--`` are the start of a comment in Lua::

  
   help([[
   The TACC modulefile defines ...
   ]])

   -- 1 --
   if (os.getenv("USER") ~= "root") then
     append_path("PATH",  ".")
   end

   -- 2 --
   load("intel", "mvapich2")

   -- 3 --
   try_load("xalt")

   -- 4 --
   -- Environment change - assume single threaded.
   if (mode() == "load" and os.getenv("OMP_NUM_THREADS") == nil) then
     setenv("OMP_NUM_THREADS","1")
   end

This modulefile shows the use of four new functions. The first one is
**append_path**.  This function is similar to **prepend_path** except
that the value is placed at the end of the path-like variable instead
of the beginning.  We add "." to our user's path at the end, except for
root.  This way our new users don't get surprised with some program in
their current directory doesn't run.  We used the **os.getenv**
function built-in to Lua to get the value of environment variable
"USER". 

The second function is **load**, this function loads the modulefiles
specified.  This function takes one or more module names.  Here we are
specifying a default compiler and mpi stack.  If the **load** function
fails to find fails to find any of it arguments, Lmod reports this as
an error and aborts.  This is in contrast with the third function, 
**try_load**, it is similar to **load** except that there is no
error reported if the module can't be found.

The fourth block of code shows how we set **OMP_NUM_THREADS**,  We wish
to set **OMP_NUM_THREADS** to have a default value of 1, but only if the
value hasn't already been set and we only want to do this when the
module is being loaded and not at any other time.  So when this module
is loaded for the first time **mode()** will return "load" and
**OMP_NUM_THREADS** won't have a value. The **setenv** will set it
to 1.  If the TACC module is unloaded, the **mode()** will be "unload"
so the if test will be false and, as a result, the **setenv** will not be
reversed.  If the user changes **OMP_NUM_THREADS** and reloads the
TACC modulefile, their value won't change because
**os.getenv("OMP_NUM_THREADS")** will return a non-nil value,
therefore the **setenv** command won't run.   Now, this is one of many
ways to set **OMP_NUM_THREADS**. Another way might be to set
**OMP_NUM_THREADS** in a file that is sourced in /etc/profile.d/ which
will also allow a default value which the user can change.
However, this example shows how to do something tricky in a modulefile. 

Typically meta modules are a single file and not versioned.  So the
TACC modulefile can be found at */apps/modulefiles/TACC.lua*.  There
is no requirement that this will be this way but it has worked well in
practice.


Modules with dependencies
-------------------------

Suppose that you have a package which needs libraries or an
application in other modulefiles.  For example, the octave application
needs gnuplot.  Let's assume that you have a separate modulefiles for
each application.  There are three ways to handle this type of
dependency: with **prereq**, **load**, or **always_load**.  It is our
view that one should definely avoid the **load** approach.  In
addition, we feel that one should adopt the **always_load**
approach.  The following is an example to show the reasons why.

Inside the octave module you can do::

    prereq("gnuplot")
    ...

So if you execute::

    $ module unload gnuplot        # 1
    $ module load octave           # 2
    $ module load gnuplot octave   # 3
    $ module unload octave         # 4

The second module command will fail, but the third one will succeed
because we have met the prerequisites.   The advantage of using prereq
is after fourth module command is executed, the gnuplot module will be
loaded.

This can be contrasted with including the load of gnuplot in the
octave modulefile::

    load("gnuplot")
    ...
   
This simplifies the loading of the octave module.  The trouble is that
when a user does the following::

    $ module load   gnuplot
    $ module load   octave
    $ module unload octave

is that after unloading *octave*, the *gnuplot* module is also unloaded.
It seems better to either use the **prereq** function shown above or
use the **always_load** function in the octave module::

    always_load("gnuplot")
    ...

Then when a user does::

    $ module load   gnuplot
    $ module load   octave
    $ module unload octave

The *gnuplot* module will still be loaded after unloading *octave*.
This will lead to the least confusion to users.

From the above example, it is clear that using the **always_load**
approach is the simpliest from the user point of view with the only
downside is that users will have an extra module loaded that they didn't
know about.
    
Fancy dependencies
------------------

Sometimes an application may depend on another application but it has
to be a certain version or newer.  Lmod can support this with the
**atleast** modifier to both **load**, **always_load** or **prereq**.  For example::

   -- Use either the always_load or prereq but not both:

   prereq(     atleast("gnuplot","5.0"))
   always_load(atleast("gnuplot","5.0"))

The **atleast** modifier to **prereq** or **always_load** will succeed
if the version of gnuplot is 5.0 or greater.


Assigning Properties
--------------------

Modules can have properties that will be displayed in a *module list* or
*module avail*.  Properties can be anything but they must be specified
in the *lmodrc.lua* file.  You are free to add to the list.  So for
example wanted to specify a module to be experimental all you need do is::

   add_property("state","experimental")

Any properties you set must be defined in the **lmodrc.lua** file. In
the source tree the properties are in init/lmodrc.lua.  A more
detailed discussion of the lmodrc.lua file can be found at :ref:`lmodrc-label`

Pushenv
-------

Lmod allows you to save the state in a stack hidden in the environment.
So if you want to set the **CC** environment variable to contain the name
of the compiler.::

   -- gcc --
   pushenv("CC","gcc")

   -- mpich --
   pushenv("CC","mpicc")

If the user executes the following::


   #                                      SETENV         PUSHENV
   $ export CC=cc;         echo $CC  # -> CC=cc          CC=cc
   $ module load   gcc;    echo $CC  # -> CC=gcc         CC=gcc
   $ module load   mpich;  echo $CC  # -> CC=mpicc       CC=mpicc
   $ module unload mpich;  echo $CC  # -> CC is unset    CC=gcc
   $ module unload gcc;    echo $CC  # -> CC is unset    CC=cc

We see that the value of **CC** is maintained as a stack variable when
we use *pushenv* but not when we use *setenv*.

Setting aliases and shell functions
-----------------------------------

Sometimes you want an set an alias as part of a module.  For example
the visit program requires the version to be specified when running
it.  So for version 2.9 of visit, the alias is set::

    set_alias("visit","visit -v 2.9")

This will expand correctly depending on the shell.  While C-shell
allows argument expansion in aliases, Bash and Zsh do not.  Bash and
Zsh use shell functions instead.  For example the visit alias could
also be written as a shell function in bash and an alias in csh::

    local bashStr = 'visit -v 2.9 "$@"'
    local cshStr  = "visit -v 2.9  $*"    
    set_shell_function("visit",bashStr,cshStr)
