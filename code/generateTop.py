import sys
D,R = int(sys.argv[1]), float(sys.argv[2])
for i in range(D*D):
	for j in range(D*D): 
		distance=(i//D-j//D)**2+(i%D-j%D)**2
		if i!=j and distance<=R*R:
			sys.stdout.write("%d %d -50.0\n" % (i,j))
