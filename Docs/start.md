# Research in understanding

## The divide

There are many ways to compare the tools used to write software. One of these commonly-used metrics is **level** &ndash; tools are sometimes considered *high*-level or *low*-level.

In computer science, these terms are most commonly used to signify how far abstracted away the tool is from the hardware it runs on. High-level tools are characterised by generalisation of problems, automatic handling of underlying system operations, portability, and reliance on low-level tools, whereas low-level tools tend to provide control over specific system details, performance, and specialisation for particular types of system.

<img src="../Assets/Level1.svg" height="350" alt="Diagram showing high-level at the top and low-level at the bottom" />

The descriptors 'high' and 'low' mean what they do because of the way nearly all software is built, relying on hardware, hardware control layers, instruction set architectures, systems languages, transport & communication protocols, interpreters, libraries, applications, user interfaces... onwards and upwards forever.

<img src="../Assets/Level2.svg" height="350" alt="A similar diagram showing how tools build upwards on top of each other." />

However, there's nothing inherently preventing software from going in the opposite direction, for example if it were useful to write a hardware simulator in a high-level language. This could allow low-level implementation details and high-level simulation logic to be expressed with a coherent system.

<img src="../Assets/Level3.svg" height="350" alt="A similar diagram showing how tools build upwards on top of each other." />

 If accurate enough, the tools used to build the system could then be built on top of the simulator. This could be done any number of times, resulting in an infinite loop of simulators built on top of themselves. This is an extremely powerful concept, though in practice isn't useful if a system isn't built with this in mind, as there will be a loss of efficiency at each level, eventually resulting in a program that is too slow (read: will not complete in the expected lifetime of the universe).

 Any simulation of a universe which contains a model of the machine used to run it cannot have the simulated machine run as fast as the physical machine, as every simulation has some level of overhead. However, it is possible to get remarkably close, which I will expand on in future.
